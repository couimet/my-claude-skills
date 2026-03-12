---
name: ensure-gitignore
version: 2026.03.12.1@cf0a4fe
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

## Design

Foundation skills (`/scratchpad`, `/question`, `/commit-msg`, `/breadcrumb`) each ensure the working directory is git-ignored before creating any file. The naive approach — read `.gitignore`, check for a sentinel string, append if missing — loads file contents into Claude's context unnecessarily. That's wasted tokens for a purely deterministic read-check-append operation.

This script executes the entire operation in one Bash call and returns a single word. Claude spends zero tokens reasoning about the algorithm. The pattern mirrors `/auto-number`: offload deterministic logic to a script, let Claude focus on decisions only it can make.
