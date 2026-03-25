---
name: ensure-gitignore
version: 2026.03.25@43a6a52
user-invocable: false
description: Ensures .gitignore contains the Claude skill working directory sentinel. Shell script handles check-and-append in one Bash call — no file contents loaded into context.
allowed-tools: Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Ensure Gitignore

Checks that `.gitignore` contains the sentinel that excludes Claude's ephemeral working directory. Appends the block if missing.

## Usage

```bash
skills/ensure-gitignore/ensure-gitignore.sh [GITIGNORE_PATH]
```

**Arguments:**

- `GITIGNORE_PATH` (optional) — path to the `.gitignore` file. Default: `.gitignore` in the current working directory.

**Output:** A single line on stdout: `present` (sentinel already exists, no change) or `added` (block was appended).

## What it adds (when missing)

```text
# Claude skill working directories
.claude-work/
```

## Idempotent

Safe to run on every foundation skill invocation. If the sentinel is already present, the script exits 0 immediately without reading the full file.
