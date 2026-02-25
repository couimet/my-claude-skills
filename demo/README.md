# Demo Site Generator

A Python build script that turns a `TIMELINE.md` narrative + numbered artifacts into a self-contained static site. The site presents each AI-assisted exchange as a scrollable card with prose, expandable artifact panels, and unified diffs between versioned files.

## Folder Structure

```
demo/
├── real-life/
│   └── issues-10/              # Raw material (source of truth)
│       ├── TIMELINE.md         # Narrative — the script's primary input
│       ├── 0001--scratchpad--*.txt
│       └── ...
├── site/                       # Generated output (gitignored, rsync-able)
│   ├── style.css               # Shared styles (all demos)
│   ├── demo.js                 # Shared JS (all demos)
│   ├── fonts/                  # Self-hosted woff2 fonts
│   └── issues-10/
│       └── index.html          # The flip-book page for this demo
├── templates/
│   ├── base.html               # HTML skeleton, head, scripts, progress bar
│   ├── card.html               # Single exchange card
│   ├── phase_divider.html      # Phase section header
│   ├── artifact.html           # Collapsible artifact panel
│   └── diff.html               # Unified diff block
├── static/
│   ├── style.css               # Source stylesheet
│   ├── demo.js                 # Source JS
│   └── fonts/                  # Source fonts (copied to site/ at build time)
├── generate.py                 # The build script
└── requirements.txt            # Python dependencies
```

`demo/site/` mirrors `demo/real-life/`: each `real-life/<name>/` directory with a TIMELINE.md produces a `site/<name>/index.html`. Shared assets live at the `site/` root and are reused across all demos.

## Running the Generator

### Install dependencies

```bash
pip install -r demo/requirements.txt
# or: pip install jinja2 mistune pygments
```

On macOS with PEP 668 (system Python), use a venv:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r demo/requirements.txt
```

### Generate

```bash
# Generate all demos
python demo/generate.py

# Generate one demo only
python demo/generate.py --demo issues-10

# Generate and preview locally
python demo/generate.py --serve
python demo/generate.py --serve --port 9000

# Print parsed TIMELINE.md structure as JSON (useful for debugging)
python demo/generate.py --debug
```

The generator writes `demo/site/` from scratch on every run. It is fully deterministic — same input always produces the same output.

## Adding a New Demo

1. Create a folder under `demo/real-life/`: `demo/real-life/<your-name>/`
2. Add a `TIMELINE.md` using the format described below
3. Place numbered artifacts alongside TIMELINE.md (same directory)
4. Run `python demo/generate.py --demo <your-name>`
5. The output appears in `demo/site/<your-name>/index.html`

## TIMELINE.md Format

The build script treats TIMELINE.md as a structured document. Heading levels and line formats are the contract — the parser is strict about these patterns.

### Document structure

```markdown
# Issue Title

## Phase 1: Phase Title

### Exchange 1 — Exchange Title

**2026-02-18 — Short description of this exchange**

Prose narrative of what happened in this exchange. Can be multiple paragraphs.
Rendered as Markdown → HTML. Supports **bold**, `code`, lists, etc.

**Artifact produced:**

- [0001--scratchpad--name-v0001.txt](0001--scratchpad--name-v0001.txt) — description

---

### Exchange 2 — Next Exchange Title
...

## Phase 2: Next Phase Title
...
```

### Parsing rules

1. **Phase headings** — `## Phase N: Title` — creates a phase divider
2. **Exchange headings** — `### Exchange N — Title` — creates a card
3. **Date line** — `**YYYY-MM-DD — description**` — card metadata; must be the first bold line after the exchange heading
4. **Prose body** — everything between the date line and any artifact reference list items becomes the narrative rendered on the card
5. **Artifact references** — `[NNNN--category--name](filename)` links are parsed to populate the artifact panels; list items matching this pattern are stripped from the prose (they appear in the artifacts section instead)

### Artifact naming convention

```
NNNN--category--basename-vNNNN.ext
```

- `NNNN` — global sequence number (chronological order across all artifacts)
- `category` — one of: `scratchpad`, `question`, `commit-msg`, `readme`, etc.
- `basename` — descriptive name slug, stable across versions
- `vNNNN` — version suffix; used to compute diffs between sequential versions

The script groups artifacts by `category--basename` and sorts by version to determine diff pairs. Version `v0001` shows full content; `v0002` and later show a unified diff against the previous version, with a toggle to see the full file.

## Visual Design Rationale

**Aesthetic direction:** Archival editorial — a technical journal meets court transcript. Designed to feel like a publication, not a generic dev-docs template.

### Typography

- **Prose:** Source Serif 4 (self-hosted woff2, no external CDN)
- **Code, numbers, labels:** JetBrains Mono (self-hosted woff2)
- Both fonts loaded with `font-display: swap` for fast first paint

### Color palette

- **Light mode:** warm parchment base (`#faf8f5`), deep ink text (`#1a1a1a`), subtle warm borders
- **Dark mode:** near-black with warm undertone (`#111110`), not cold GitHub dark — different palette, not just inverted
- **Phase accents:** five muted editorial colors (deep blue, teal, forest green, amber, muted purple) — brightened for dark mode but keeping the same hue family

All colors are CSS custom properties. Dark mode is `@media (prefers-color-scheme: dark)` — follows system preference, no toggle.

### Card anatomy

Each exchange card contains:
1. **Gutter** — exchange number in monospace, vertically centered on the timeline spine
2. **Phase badge** — color-coded pill with phase title, truncated to 24 chars
3. **Date** — `YYYY-MM-DD` in monospace
4. **Title** — exchange title in serif at 1.3rem
5. **Prose** — TIMELINE.md narrative rendered as Markdown → HTML
6. **Artifact panels** — collapsible; default closed with JS, default open without JS (progressive enhancement)

### Diff strategy

- First version of an artifact: full content with Pygments syntax highlighting
- Subsequent versions: unified diff view by default, toggle to full content
- Diff line coloring: green add / red remove, mapped to CSS vars (both modes)
- "diff" badge on the toggle button signals which artifacts have changed

### Motion

- Card entrance: `card-enter` keyframe animation at 0.4s ease
- Artifact panel collapse: `transition: max-height 0.3s ease`
- Both disabled via `@media (prefers-reduced-motion: reduce)`

## Deployment

The `demo/site/` directory is fully self-contained. No build server, no CDN, no runtime dependencies.

### GitHub Pages

1. Repo Settings → Pages → Source: "Deploy from a branch"
2. Branch: `main`, folder: `/demo/site`
3. Optional custom domain: add `demo/site/CNAME` containing `my-claude-skills.ouimet.info`
4. DNS: CNAME record `my-claude-skills.ouimet.info` → `couimet.github.io`

For `demo/site/` to be available from `main`, you need to regenerate and commit it before merging — or use a GitHub Actions workflow to run `python demo/generate.py` on push.

### ouimet.info (VPS)

```bash
rsync -avz --delete demo/site/ user@ouimet.info:/var/www/my-claude-skills/
```

Both targets serve identical static files. GitHub Pages for always-current preview; ouimet.info for the branded production URL.

## Future Scope

**`/generate-demo-narrative` skill** — a companion Claude Code skill to help author TIMELINE.md entries: read unreferenced artifacts, draft new exchange entries, validate all artifact links point to existing files, flag version gaps. Not implemented yet — the generator works with hand-authored TIMELINE.md.

**Multi-demo index** — when a second demo exists under `real-life/`, add a root `demo/site/index.html` generator that renders a card grid linking to each demo.
