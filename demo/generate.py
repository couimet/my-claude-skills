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
                prose: str (raw markdown)
                artifacts: list of dicts with:
                    sequence: str (e.g. "0001")
                    category: str
                    basename: str
                    version: str (e.g. "v0001")
                    filename: str
    """
    # Stub — full parser implemented in S002.
    return {
        "title": "Demo",
        "phases": [],
    }


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
