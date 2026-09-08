---
name: note
version: 2026.09.03@a8dc4ea
description: Capture a note, finding, or result in a timestamped file under .claude-work/. Lightweight alternative to /scratchpad
argument-hint: <description>
allowed-tools: Read, Write, Glob, Bash(*/skills/issue-context/get-issue-folder-path.sh *), Bash(mkdir -p *), Bash(date *)
---

# Note

Capture a note, finding, or result in a lightweight timestamped file. Use this instead of `/scratchpad` when you need to record something without implementation plans, step tracking, or structured formats.

**Input:** $ARGUMENTS (a short description for the filename)

## Step 1: Determine Target Directory and Timestamp

Resolve the work-item folder with `get-issue-folder-path.sh`, which reads the current branch and honors the configured `segment` (it detects git worktrees and returns the shared `.claude-work/` location). Run it and `date` as parallel tool calls — they are independent:

```bash
~/.claude/skills/issue-context/get-issue-folder-path.sh
```

```bash
date +%Y%m%d-%H%M%S
```

Use the stdout of `get-issue-folder-path.sh` as `<folder>` and write notes to `<folder>/notes/`. The script prints a different `<folder>` per branch context:

- **On a work branch** (a configured `branchPatterns` entry matches, e.g. `issues/42`): the segment-aware folder `<base>/<segment>/<ID>`, so notes land at `<base>/<segment>/<ID>/notes/` (under the default segment, `<base>/issues/42/notes/`).
- **Otherwise** (main, or any branch matching no pattern): the bare root `<base>`, so notes land at `<base>/notes/`.

Create the notes directory if it doesn't exist:

```bash
mkdir -p <folder>/notes/
```

## Step 2: Generate Filename

Build the filename using the timestamp from Step 1 and a slug derived from $ARGUMENTS:

Slug rules: lowercase $ARGUMENTS, replace spaces and special characters with hyphens, collapse consecutive hyphens, trim leading/trailing hyphens. Keep it under 50 characters.

**Filename:** `<YYYYMMDD-HHMMSS>-<slug>.txt`

Example: `20260329-143022-api-audit-findings.txt`

## Step 3: Write the File

See `/pre-write` for the think-before-writing rule: complete all reasoning before writing the first word.

Write the note content to the file. The format is freeform. Structure it however best fits the content being captured. There are no required sections or templates.

**The one rule: each paragraph is ONE continuous line.** No line breaks at 72, 80, or any fixed column. Use line breaks only for structural separation (between paragraphs, around lists, around code blocks). Override your default instinct to wrap.

Formatting: see `/prose-style` for the full hard-wrap rationale and for code-reference and GitHub-reference rules.

### Output Anchors

Format: freeform text.
Length: unlimited.
Perspective: whatever fits the content being captured.

Before printing the path in Step 4, re-read the file and verify no paragraph contains a mid-sentence line break. Rewrite any that do.
Also skim for AI-writing tells: em dashes, filler phrases (in order to, due to the fact that), vague attributions, generic positive conclusions. Rewrite any you find.

## Step 4: Confirm

Print only the absolute filepath:

```text
<folder>/notes/<filename>
```

Do NOT print the file contents.
