---
name: issue-context
version: 2026.06.25@7353cfe
user-invocable: false
description: Contract for target-path.sh and claude-work-root.sh, the shell scripts that resolve .claude-work/ file paths from the current git branch. Referenced by name from /scratchpad, /question, /commit-msg; not auto-consulted.
allowed-tools: Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/issue-context/claude-work-root.sh *)
---

# Issue Context

All deterministic logic for "where should this file go?" lives in the scripts. Skills that write numbered working files call `target-path.sh`; skills that only need the `.claude-work/` root directory call `claude-work-root.sh`.

## Script: target-path.sh

## Script contract

```bash
~/.claude/skills/issue-context/target-path.sh --type <scratchpads|questions|commit-msgs|notes> --description "<text>" [--ext txt]
```

The script reads the current branch, extracts the issue ID (numeric prefix of the segment after `issues/` when applicable, full segment otherwise, empty on non-issue branches), slugifies the description, runs `auto-number.sh` internally, creates the target directory, and prints the full file path on stdout.

- On `issues/<ID>` branches: `.claude-work/issues/<ID>/<type>/NNNN-<slug>.<ext>`
- Everywhere else: `.claude-work/<type>/NNNN-<slug>.<ext>`

## Script: claude-work-root.sh

```bash
~/.claude/skills/issue-context/claude-work-root.sh
```

Returns the absolute path to the `.claude-work/` root directory, taking git worktrees into account. In the primary checkout `.claude-work/` lives at `--show-toplevel` (same as before). In a linked worktree (detected by comparing `--git-dir` against `--git-common-dir`), `.claude-work/` lives at the main checkout root so all worktrees share a single copy.

The script outputs an absolute path on stdout (e.g., `/Users/x/project/.claude-work`). The directory is NOT created by this script — callers handle that.

Skills that need the `.claude-work/` root but don't use `target-path.sh` (like `/note` and `/breadcrumb`) call this script directly to get the base directory, then append their subdirectory and filename.

## Breadcrumbs

`/breadcrumb` writes to a single file per issue (not a numbered sequence), so it does not use `target-path.sh`. It calls `claude-work-root.sh` to get the base directory, then writes to `<base>/issues/<ID>/breadcrumb.md` or `<base>/breadcrumb-<slug>.md`.

## History

Before the refactor in [issues/120](https://github.com/couimet/my-claude-skills/issues/120), this file contained ~118 lines of Markdown that restated the branch-parsing rules in prose, and those same rules were also inlined into `/scratchpad`, `/question`, and `/commit-msg`. The audit concluded that deterministic logic belongs in a shell script (the pattern set by `/auto-number` and `/ensure-gitignore`), not in Markdown auto-consulted for every file-creation task. This file is now a pointer to the script.
