---
name: note
version: 2026.04.24@2423d79
description: Capture a quick note, finding, or result in a timestamped file under .claude-work/ — lightweight alternative to /scratchpad with no foundation skill dependencies
argument-hint: <description>
allowed-tools: Read, Write, Glob, Bash(git branch --show-current), Bash(mkdir -p *), Bash(date *)
---

# Note

Capture a note, finding, or result in a lightweight timestamped file. Use this instead of `/scratchpad` when you need to record something without implementation plans, step tracking, or structured formats.

**Input:** $ARGUMENTS (a short description for the filename)

## Step 1: Determine Target Directory and Timestamp

Run both commands as parallel tool calls — they are independent:

```bash
git branch --show-current
```

```bash
date +%Y%m%d-%H%M%S
```

If the branch starts with `issues/`, extract the issue number (characters after `issues/` up to the first `-` or `_`, only if those characters are purely numeric; otherwise use the full string after `issues/`):

- **On an issue branch:** `.claude-work/issues/<ID>/notes/`
- **Otherwise:** `.claude-work/notes/`

Create the directory if it doesn't exist:

```bash
mkdir -p <target-directory>
```

## Step 2: Generate Filename

Build the filename using the timestamp from Step 1 and a slug derived from $ARGUMENTS:

Slug rules: lowercase $ARGUMENTS, replace spaces and special characters with hyphens, collapse consecutive hyphens, trim leading/trailing hyphens. Keep it under 50 characters.

**Filename:** `<YYYYMMDD-HHMMSS>-<slug>.txt`

Example: `20260329-143022-api-audit-findings.txt`

## Step 3: Write the File

Write the note content to the file. The format is freeform — structure it however best fits the content being captured. There are no required sections or templates.

**The one rule: each paragraph is ONE continuous line.** No line breaks at 72, 80, or any fixed column. Use line breaks only for structural separation (between paragraphs, around lists, around code blocks). Override your default instinct to wrap.

Before printing the path in Step 4, re-read the file and verify no paragraph contains a mid-sentence line break. Rewrite any that do.

## Step 4: Confirm

Print only the filepath:

```text
<target-directory>/<filename>
```

Do NOT print the file contents.
