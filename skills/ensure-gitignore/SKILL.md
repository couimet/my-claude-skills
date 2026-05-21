---
name: ensure-gitignore
version: 2026.05.15@4fe4598
user-invocable: false
description: Ensures the project root .gitignore contains the Claude skill working directory sentinel. Shell script handles check-and-append in one Bash call. No file contents loaded into context.
allowed-tools: Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Ensure Gitignore

Checks that the project root `.gitignore` contains the sentinel that excludes Claude's ephemeral working directory. Appends the block if missing. Always targets the git repository root — never creates or modifies `.gitignore` files in subdirectories.

## Usage

```bash
~/.claude/skills/ensure-gitignore/ensure-gitignore.sh [GITIGNORE_PATH]
```

**Arguments:**

- `GITIGNORE_PATH` (optional): path to the `.gitignore` file. Default: the git repository root's `.gitignore` (resolved via `git rev-parse --show-toplevel`). The script never creates or modifies `.gitignore` files in subdirectories.

**Output:** A single line on stdout: `present` (sentinel already exists, no change) or `added` (block was appended).

## What it adds (when missing)

```text
# Claude skill working directories
.claude-work/
```

## Idempotent

Safe to run on every foundation skill invocation. If the sentinel is already present, the script exits 0 immediately without reading the full file.
