---
name: issue-context
version: 2026.04.22@28de7f8
user-invocable: false
description: Contract for target-path.sh — the shell script that resolves .claude-work/ file paths from the current git branch. Referenced by name from /scratchpad, /question, /commit-msg; not auto-consulted.
allowed-tools: Bash(*/skills/issue-context/target-path.sh *)
---

# Issue Context

All deterministic logic for "where should this file go?" lives in `target-path.sh`. Skills that write numbered working files call the script; nothing reasons about branch names in Markdown.

## Script contract

```bash
~/.claude/skills/issue-context/target-path.sh --type <scratchpads|questions|commit-msgs> --description "<text>" [--ext txt]
```

The script reads the current branch, extracts the issue ID (numeric prefix of the segment after `issues/` when applicable, full segment otherwise, empty on non-issue branches), slugifies the description, runs `auto-number.sh` internally, creates the target directory, and prints the full file path on stdout.

- On `issues/<ID>` branches: `.claude-work/issues/<ID>/<type>/NNNN-<slug>.<ext>`
- Everywhere else: `.claude-work/<type>/NNNN-<slug>.<ext>`

## Breadcrumbs

`/breadcrumb` writes to a single file per issue (not a numbered sequence), so it does not use `target-path.sh`. It detects the branch directly and writes to `.claude-work/issues/<ID>/breadcrumb.md` or `.claude-work/breadcrumb-<slug>.md`.

## History

Before the refactor in [issues/120](https://github.com/couimet/my-claude-skills/issues/120), this file contained ~118 lines of Markdown that restated the branch-parsing rules in prose — and those same rules were also inlined into `/scratchpad`, `/question`, and `/commit-msg`. The audit concluded that deterministic logic belongs in a shell script (the pattern set by `/auto-number` and `/ensure-gitignore`), not in Markdown auto-consulted for every file-creation task. This file is now a pointer to the script.
