#!/usr/bin/env python3
"""
Demo site generator.

Reads demo/real-life/<name>/TIMELINE.md and numbered artifacts,
then generates a self-contained static site in demo/site/<name>/.

Usage:
    python demo/generate.py                  # Generate all demos
    python demo/generate.py --demo issues-10 # Generate one demo
    python demo/generate.py --serve          # Generate and serve locally
    python demo/generate.py --debug          # Print parsed structure as JSON
"""

import argparse
import http.server
import json
import os
import re
import shutil
import sys
from pathlib import Path

try:
    from jinja2 import Environment, FileSystemLoader
except ImportError:
    sys.exit("Missing dependency: pip install jinja2")

# Project root is one level above this script's directory.
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR
REAL_LIFE_DIR = PROJECT_ROOT / "real-life"
SITE_DIR = PROJECT_ROOT / "site"
TEMPLATES_DIR = PROJECT_ROOT / "templates"
STATIC_DIR = PROJECT_ROOT / "static"


def discover_demos(only=None):
    """Find demo directories under real-life/ that contain TIMELINE.md."""
    demos = []
    if not REAL_LIFE_DIR.is_dir():
        return demos
    for entry in sorted(REAL_LIFE_DIR.iterdir()):
        if entry.is_dir() and (entry / "TIMELINE.md").is_file():
            if only is None or entry.name == only:
                demos.append(entry)
    return demos


# --- Regex patterns for TIMELINE.md parsing ---
RE_H1 = re.compile(r"^#\s+(.+)$")
RE_PHASE = re.compile(r"^##\s+Phase\s+(\d+):\s+(.+)$")
RE_EXCHANGE = re.compile(r"^###\s+Exchange\s+(\d+)\s+—\s+(.+)$")
RE_DATE = re.compile(r"^\*\*(\d{4}-\d{2}-\d{2})\s+—\s+(.+?)\*\*$")
RE_ARTIFACT_LINK = re.compile(
    r"\[(\d{4})--([a-z-]+)--(.+?)\]\(([^)]+)\)"
)
RE_ARTIFACT_VERSION = re.compile(r"-v(\d{4})\.[a-z]+$")


def parse_artifact_ref(match):
    """Parse a single artifact reference from a regex match on RE_ARTIFACT_LINK."""
    sequence = match.group(1)
    category = match.group(2)
    raw_name = match.group(3)
    filename = match.group(4)

    # Extract version from filename if present.
    ver_match = RE_ARTIFACT_VERSION.search(filename)
    version = f"v{ver_match.group(1)}" if ver_match else None

    # Derive basename by stripping the version suffix from the raw link text.
    # e.g. "0004-readme-enrichment-plan-v0001.txt" -> "0004-readme-enrichment-plan"
    basename = raw_name
    if ver_match:
        basename = re.sub(r"-v\d{4}\.[a-z]+$", "", raw_name)

    return {
        "sequence": sequence,
        "category": category,
        "basename": basename,
        "version": version,
        "filename": filename,
    }


def parse_timeline(timeline_path):
    """Parse TIMELINE.md into a structured dict.

    Returns a dict with:
        title: str - from the H1 heading
        phases: list of dicts, each with:
            number: int
            title: str
            exchanges: list of dicts, each with:
                number: int
                title: str
                date: str
                date_description: str
                prose: str (raw markdown of the narrative body)
                artifacts: list of dicts with:
                    sequence: str (e.g. "0001")
                    category: str (e.g. "scratchpad")
                    basename: str (e.g. "0004-readme-enrichment-plan")
                    version: str or None (e.g. "v0001")
                    filename: str (the link target)
    """
    text = timeline_path.read_text(encoding="utf-8")
    lines = text.split("\n")

    title = ""
    phases = []
    current_phase = None
    current_exchange = None

    # Accumulator for prose lines within an exchange.
    prose_lines = []
    # Track whether we've seen the date line for the current exchange.
    seen_date = False

    def flush_prose():
        """Save accumulated prose to the current exchange."""
        nonlocal prose_lines
        if current_exchange is not None and prose_lines:
            current_exchange["prose"] = "\n".join(prose_lines).strip()
        prose_lines = []

    for line in lines:
        # H1: document title.
        m = RE_H1.match(line)
        if m and not title:
            title = m.group(1).strip()
            continue

        # Phase heading.
        m = RE_PHASE.match(line)
        if m:
            flush_prose()
            current_phase = {
                "number": int(m.group(1)),
                "title": m.group(2).strip(),
                "exchanges": [],
            }
            phases.append(current_phase)
            current_exchange = None
            seen_date = False
            continue

        # Exchange heading.
        m = RE_EXCHANGE.match(line)
        if m:
            flush_prose()
            current_exchange = {
                "number": int(m.group(1)),
                "title": m.group(2).strip(),
                "date": "",
                "date_description": "",
                "prose": "",
                "artifacts": [],
            }
            if current_phase is not None:
                current_phase["exchanges"].append(current_exchange)
            seen_date = False
            continue

        # Date line within an exchange.
        m = RE_DATE.match(line)
        if m and current_exchange is not None and not seen_date:
            current_exchange["date"] = m.group(1)
            current_exchange["date_description"] = m.group(2).strip()
            seen_date = True
            continue

        # Artifact references (can appear anywhere in the exchange body).
        if current_exchange is not None:
            for art_match in RE_ARTIFACT_LINK.finditer(line):
                current_exchange["artifacts"].append(
                    parse_artifact_ref(art_match)
                )

        # Accumulate prose lines (skip horizontal rules and blank-only sections
        # at the start, but keep everything else).
        if current_exchange is not None and seen_date:
            # Skip the "---" dividers between exchanges.
            if line.strip() == "---":
                continue
            prose_lines.append(line)

    # Flush any remaining prose from the last exchange.
    flush_prose()

    return {
        "title": title,
        "phases": phases,
    }


def group_artifacts_for_diffing(phases):
    """Group all artifacts across phases by category+basename for diff pairing.

    Returns a dict mapping "category--basename" to a list of artifact dicts
    sorted by version, enabling sequential diff computation in S004.
    """
    groups = {}
    for phase in phases:
        for exchange in phase["exchanges"]:
            for art in exchange["artifacts"]:
                key = f"{art['category']}--{art['basename']}"
                if key not in groups:
                    groups[key] = []
                groups[key].append(art)

    # Sort each group by version.
    for key in groups:
        groups[key].sort(key=lambda a: a["version"] or "")

    return groups


def build_demo(demo_dir, env):
    """Generate the site for a single demo directory."""
    timeline_path = demo_dir / "TIMELINE.md"
    demo_name = demo_dir.name
    output_dir = SITE_DIR / demo_name

    # Parse the timeline.
    data = parse_timeline(timeline_path)

    # Prepare output directory.
    output_dir.mkdir(parents=True, exist_ok=True)

    # Compute relative path from output_dir to SITE_DIR for shared assets.
    css_path = "../style.css"
    js_path = "../demo.js"

    # Render the page.
    template = env.get_template("base.html")
    html = template.render(
        title=data.get("title", f"Demo: {demo_name}"),
        subtitle="A real-time record of Claude Code skills in action",
        description="Step-by-step walkthrough of how Claude Code skills were used to build a real project.",
        css_path=css_path,
        js_path=js_path,
        content="<!-- Exchange cards will be rendered here by S003 -->",
    )

    index_path = output_dir / "index.html"
    index_path.write_text(html, encoding="utf-8")
    print(f"  Generated {index_path.relative_to(PROJECT_ROOT)}")


def copy_static_assets():
    """Copy shared CSS and JS to the site root."""
    SITE_DIR.mkdir(parents=True, exist_ok=True)
    for filename in ["style.css", "demo.js"]:
        src = STATIC_DIR / filename
        dst = SITE_DIR / filename
        if src.is_file():
            shutil.copy2(src, dst)
    print(f"  Copied static assets to {SITE_DIR.relative_to(PROJECT_ROOT)}/")


def serve(port=8000):
    """Start a local HTTP server for previewing the generated site."""
    os.chdir(SITE_DIR)
    handler = http.server.SimpleHTTPRequestHandler
    server = http.server.HTTPServer(("", port), handler)
    print(f"Serving demo site at http://localhost:{port}/")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


def main():
    parser = argparse.ArgumentParser(description="Generate demo site from TIMELINE.md artifacts.")
    parser.add_argument("--demo", type=str, default=None, help="Generate only this demo (e.g. issues-10)")
    parser.add_argument("--serve", action="store_true", help="Start local HTTP server after generating")
    parser.add_argument("--debug", action="store_true", help="Print parsed timeline structure as JSON")
    parser.add_argument("--port", type=int, default=8000, help="Port for --serve (default: 8000)")
    args = parser.parse_args()

    demos = discover_demos(only=args.demo)
    if not demos:
        target = f" '{args.demo}'" if args.demo else ""
        sys.exit(f"No demos found{target} under {REAL_LIFE_DIR.relative_to(PROJECT_ROOT)}/")

    # Set up Jinja2 environment.
    env = Environment(
        loader=FileSystemLoader(str(TEMPLATES_DIR)),
        autoescape=True,
    )

    if args.debug:
        for demo_dir in demos:
            data = parse_timeline(demo_dir / "TIMELINE.md")
            # Summary stats.
            total_exchanges = sum(len(p["exchanges"]) for p in data["phases"])
            total_artifacts = sum(
                len(e["artifacts"])
                for p in data["phases"]
                for e in p["exchanges"]
            )
            groups = group_artifacts_for_diffing(data["phases"])
            print(f"Title: {data['title']}")
            print(f"Phases: {len(data['phases'])}")
            print(f"Exchanges: {total_exchanges}")
            print(f"Artifact references: {total_artifacts}")
            print(f"Artifact groups (for diffing): {len(groups)}")
            print()
            print(json.dumps(data, indent=2))
        return

    print("Generating demo site...")
    copy_static_assets()
    for demo_dir in demos:
        print(f"\n  Processing {demo_dir.name}/")
        build_demo(demo_dir, env)

    print("\nDone.")

    if args.serve:
        serve(port=args.port)


if __name__ == "__main__":
    main()
