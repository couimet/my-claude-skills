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
import difflib
import http.server
import json
import os
import re
import shutil
import sys
from pathlib import Path

try:
    from jinja2 import Environment, FileSystemLoader
    from markupsafe import Markup
except ImportError:
    sys.exit("Missing dependency: pip install jinja2")

try:
    import mistune
except ImportError:
    sys.exit("Missing dependency: pip install mistune")

try:
    from pygments import highlight
    from pygments.formatters import HtmlFormatter
    from pygments.lexers import get_lexer_for_filename, TextLexer
except ImportError:
    sys.exit("Missing dependency: pip install pygments")

# Module-level Markdown renderer — instantiated once, reused on every call to
# render_prose() to avoid repeated parser/renderer construction overhead.
_md = mistune.create_markdown()

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
    # Accumulator for intro lines between a phase heading and its first exchange.
    phase_intro_lines = []
    # Track whether we've seen the date line for the current exchange.
    seen_date = False

    def flush_prose():
        """Save accumulated prose to the current exchange."""
        nonlocal prose_lines
        if current_exchange is not None and prose_lines:
            current_exchange["prose"] = "\n".join(prose_lines).strip()
        prose_lines = []

    def flush_phase_intro():
        """Save accumulated phase intro lines to the current phase."""
        nonlocal phase_intro_lines
        if current_phase is not None and phase_intro_lines:
            current_phase["intro"] = "\n".join(phase_intro_lines).strip()
        phase_intro_lines = []

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
            flush_phase_intro()
            current_phase = {
                "number": int(m.group(1)),
                "title": m.group(2).strip(),
                "intro": "",
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
            flush_phase_intro()
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

        # Accumulate phase intro lines (between ## phase heading and first ### exchange).
        if current_phase is not None and current_exchange is None:
            if line.strip() not in ("", "---"):
                phase_intro_lines.append(line)
            continue

        # Accumulate prose lines (skip horizontal rules, artifact reference
        # lines, and blank-only sections at the start).
        if current_exchange is not None and seen_date:
            # Skip the "---" dividers between exchanges.
            if line.strip() == "---":
                continue
            # Skip lines that are artifact reference list items — these are
            # displayed separately in the card-artifacts section.
            if RE_ARTIFACT_LINK.search(line) and line.lstrip().startswith("- ["):
                continue
            prose_lines.append(line)

    # Flush any remaining prose from the last exchange or phase intro.
    flush_prose()
    flush_phase_intro()

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


def highlight_content(content, filename):
    """Syntax-highlight file content using Pygments."""
    try:
        lexer = get_lexer_for_filename(filename, stripall=True)
    except Exception:
        lexer = TextLexer(stripall=True)
    formatter = HtmlFormatter(nowrap=True, classprefix="hl-")
    return highlight(content, lexer, formatter)


def compute_diff(old_content, new_content, old_name, new_name):
    """Compute a unified diff between two file contents.

    Returns a list of diff line dicts with 'type' (add/remove/context/header)
    and 'content' fields.
    """
    # keepends=True is required here: unified_diff with lineterm="" suppresses
    # its own newline appending, so input lines must already carry their own
    # line endings. Without keepends=True, context lines in the diff output
    # would have no trailing newline and rstrip("\n") below would strip nothing
    # — but more importantly, unified_diff would concatenate lines incorrectly.
    old_lines = old_content.splitlines(keepends=True)
    new_lines = new_content.splitlines(keepends=True)

    diff_lines = list(difflib.unified_diff(
        old_lines, new_lines,
        fromfile=old_name, tofile=new_name,
        lineterm="",
    ))

    result = []
    for line in diff_lines:
        text = line.rstrip("\n")
        if line.startswith("@@"):
            result.append({"type": "hunk", "content": text})
        elif line.startswith("---") or line.startswith("+++"):
            result.append({"type": "header", "content": text})
        elif line.startswith("+"):
            result.append({"type": "add", "content": text[1:]})
        elif line.startswith("-"):
            result.append({"type": "remove", "content": text[1:]})
        else:
            # Context line — strip leading space.
            result.append({"type": "context", "content": text[1:] if text.startswith(" ") else text})

    return result


def enrich_artifacts(phases, demo_dir):
    """Read artifact file contents and compute diffs for versioned artifacts.

    Mutates each artifact dict in-place, adding:
      - content: raw file content (str)
      - highlighted_html: Pygments-highlighted HTML (str)
      - diff_lines: list of diff line dicts (if a previous version exists)
      - prev_filename: the previous version's filename (if diff exists)
      - is_first_version: True if this is v0001 or unversioned
    """
    # Build the version group index: category--basename -> [artifact, ...]
    groups = group_artifacts_for_diffing(phases)

    # Build a lookup from filename -> content for diff computation.
    content_cache = {}

    for phase in phases:
        for exchange in phase["exchanges"]:
            for art in exchange["artifacts"]:
                filepath = demo_dir / art["filename"]
                if filepath.is_file():
                    content = filepath.read_text(encoding="utf-8", errors="replace")
                else:
                    content = f"(file not found: {art['filename']})"

                art["content"] = content
                art["highlighted_html"] = Markup(highlight_content(content, art["filename"]))
                content_cache[art["filename"]] = content

                # Determine if this is the first version.
                key = f"{art['category']}--{art['basename']}"
                group = groups.get(key, [])
                idx = next(
                    (i for i, a in enumerate(group) if a["filename"] == art["filename"]),
                    0,
                )
                art["is_first_version"] = (idx == 0)

                # Compute diff against previous version if one exists.
                if idx > 0:
                    prev = group[idx - 1]
                    prev_content = content_cache.get(prev["filename"], "")
                    art["diff_lines"] = compute_diff(
                        prev_content, content,
                        prev["filename"], art["filename"],
                    )
                    art["prev_filename"] = prev["filename"]
                else:
                    art["diff_lines"] = []
                    art["prev_filename"] = None


def render_prose(markdown_text):
    """Convert Markdown prose to HTML using mistune."""
    return _md(markdown_text)


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

    # Compute stats.
    total_exchanges = sum(len(p["exchanges"]) for p in data["phases"])
    total_artifacts = sum(
        len(e["artifacts"])
        for p in data["phases"]
        for e in p["exchanges"]
    )

    # Enrich artifacts with file content, highlighting, and diffs.
    enrich_artifacts(data["phases"], demo_dir)

    # Render exchange cards and phase dividers.
    card_template = env.get_template("card.html")
    phase_template = env.get_template("phase_divider.html")
    artifact_template = env.get_template("artifact.html")
    diff_template = env.get_template("diff.html")

    content_parts = []
    for phase in data["phases"]:
        # Phase divider.
        content_parts.append(phase_template.render(phase=phase))

        # Exchange cards.
        for exchange in phase["exchanges"]:
            # Convert prose markdown to HTML.
            exchange["prose_html"] = Markup(render_prose(exchange.get("prose", "")))

            # Render artifact panels.
            artifact_panels = []
            for art in exchange.get("artifacts", []):
                # Render diff block if diff lines exist.
                diff_html = Markup("")
                if art.get("diff_lines"):
                    diff_html = Markup(diff_template.render(diff_lines=art["diff_lines"]))

                panel_html = artifact_template.render(
                    artifact=art,
                    diff_html=diff_html,
                )
                artifact_panels.append(Markup(panel_html))
            exchange["artifact_panels"] = artifact_panels

            content_parts.append(card_template.render(
                exchange=exchange,
                phase=phase,
            ))

    content_html = Markup("\n".join(content_parts))

    # Render the page.
    template = env.get_template("base.html")
    html = template.render(
        title=data.get("title", f"Demo: {demo_name}"),
        subtitle="Every exchange, every artifact, every diff — captured as it happened.",
        description=f"A real-time case study of building {data.get('title', demo_name)} with Claude Code skills.",
        css_path=css_path,
        js_path=js_path,
        content=content_html,
        phases=data["phases"],
        exchange_count=total_exchanges,
        phase_count=len(data["phases"]),
        artifact_count=total_artifacts,
    )

    index_path = output_dir / "index.html"
    index_path.write_text(html, encoding="utf-8")
    print(f"  Generated {index_path.relative_to(PROJECT_ROOT)}")


def build_landing(demo_dirs, env):
    """Generate demo/site/index.html — a landing page listing all demos."""
    demos = []
    for demo_dir in demo_dirs:
        data = parse_timeline(demo_dir / "TIMELINE.md")
        total_exchanges = sum(len(p["exchanges"]) for p in data["phases"])
        total_artifacts = sum(
            len(e["artifacts"])
            for p in data["phases"]
            for e in p["exchanges"]
        )
        demos.append({
            "name": demo_dir.name,
            "title": data.get("title", demo_dir.name),
            "phase_count": len(data["phases"]),
            "exchange_count": total_exchanges,
            "artifact_count": total_artifacts,
            "url": f"{demo_dir.name}/index.html",
        })

    template = env.get_template("landing.html")
    html = template.render(demos=demos)
    index_path = SITE_DIR / "index.html"
    index_path.write_text(html, encoding="utf-8")
    print(f"  Generated {index_path.relative_to(PROJECT_ROOT)}")


def copy_static_assets():
    """Copy shared CSS, JS, and fonts to the site root."""
    SITE_DIR.mkdir(parents=True, exist_ok=True)
    for filename in ["style.css", "demo.js"]:
        src = STATIC_DIR / filename
        dst = SITE_DIR / filename
        if src.is_file():
            shutil.copy2(src, dst)

    # Copy fonts directory.
    fonts_src = STATIC_DIR / "fonts"
    fonts_dst = SITE_DIR / "fonts"
    if fonts_src.is_dir():
        if fonts_dst.exists():
            shutil.rmtree(fonts_dst)
        shutil.copytree(fonts_src, fonts_dst)

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
    env.filters["markdown"] = render_prose

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

    # Landing page — only when generating all demos (not --demo <single>).
    if args.demo is None:
        all_demos = discover_demos()
        build_landing(all_demos, env)

    print("\nDone.")

    if args.serve:
        serve(port=args.port)


if __name__ == "__main__":
    main()
