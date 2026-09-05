---
name: issue-context
version: 2026.09.03@a8dc4ea
user-invocable: false
description: Contract for the issue-context shell scripts that resolve .claude-work/ file paths from the current git branch and from the configurable work-item settings. Referenced by name from /scratchpad, /question, /commit-msg; not auto-consulted.
allowed-tools: Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/issue-context/claude-work-root.sh *), Bash(*/skills/issue-context/resolve-issue-id.sh *), Bash(*/skills/issue-context/branch-issue-id.sh *), Bash(*/skills/issue-context/get-issue-folder-path.sh *)
---

# Issue Context

All deterministic logic for "where should this file go?" lives in the scripts. Skills that write numbered working files call `target-path.sh`. Skills that only need the `.claude-work/` root directory call `claude-work-root.sh`.

## Script: target-path.sh

## Script contract

```bash
~/.claude/skills/issue-context/target-path.sh --type <scratchpads|questions|commit-msgs|notes> --description "<text>" [--ext txt]
```

The script reads the current branch and extracts the issue ID (numeric prefix of the segment after `issues/` when applicable, full segment otherwise, empty on non-issue branches). It slugifies the description, runs `auto-number.sh` internally, creates the target directory, and prints the absolute file path on stdout.

- On `issues/<ID>` branches: absolute path ending in `.claude-work/issues/<ID>/<type>/NNNN-<slug>.<ext>`
- Everywhere else: absolute path ending in `.claude-work/<type>/NNNN-<slug>.<ext>`

## Script: claude-work-root.sh

```bash
~/.claude/skills/issue-context/claude-work-root.sh
```

Returns the absolute path to the `.claude-work/` root directory, taking git worktrees into account. In the primary checkout `.claude-work/` lives at `--show-toplevel` (same as before). In a linked worktree (detected by comparing `--git-dir` against `--git-common-dir`), `.claude-work/` lives at the main checkout root so all worktrees share a single copy.

The script outputs an absolute path on stdout (e.g., `/Users/x/project/.claude-work`). The directory is NOT created by this script. Callers handle that.

Skills that need the `.claude-work/` root but don't use `target-path.sh` (like `/note` and `/breadcrumb`) call this script directly to get the base directory. They append their subdirectory and filename.

## Settings: issue-settings.sh

The work-item path convention is configurable through `~/.my-claude-skills/settings.json`, whose path is overridable with `MY_CLAUDE_SKILLS_CONFIG` (which must hold a full path to the file). `issue-settings.sh` locates and parses that file and exposes the result as `SETTINGS_*` globals; scripts source it rather than execute it. Any failure — missing file, malformed JSON, invalid regex in a pattern entry — writes a warning to stderr and resolves to the built-in defaults, never refusing to resolve. Keys and defaults:

- `segment` — directory name under the `.claude-work/` root that holds work-item folders; default `issues`. An explicit empty string omits the directory.
- `branchPatterns` — ordered EREs matched against branch names; first match wins and capture group one is the identifier. Defaults to the five-row list in the settings file: `^issues/([0-9]+)[-_]`, `^issues/([0-9]+)$`, `^issues/([A-Za-z][A-Za-z0-9]*-[0-9]+)`, `^issues/(.+)$`, `^([A-Za-z][A-Za-z0-9]*-[0-9]+)`.
- `branchTemplate` — branch name built from an identifier; default `issues/{id}`.
- `urlPatterns` — ordered EREs matched against tracker URLs; first match wins and capture group one is the identifier. Defaults to `/issues/([0-9]+)`, `/browse/([A-Z][A-Z0-9]+-[0-9]+)`.
- `version` — settings schema version; default `1`.

## Script: resolve-issue-id.sh

```bash
~/.claude/skills/issue-context/resolve-issue-id.sh <URL-or-identifier>
```

Resolves a single argument to a canonical work-item identifier. A value with a URL shape (it contains a scheme like `https://`) is matched against `urlPatterns` in order; the first pattern that matches supplies the identifier as its first capture group. A value without a URL shape is a bare identifier and is printed verbatim after a safety check: it must be usable as one path segment and one branch segment (non-empty, no leading/trailing dot or slash, no whitespace). A URL-shaped value matching no pattern, an unsafe identifier, or the wrong argument count prints an error to stderr and exits 1 — refusing is safer than inventing an identifier. Output is a single line on stdout.

## Script: branch-issue-id.sh

```bash
~/.claude/skills/issue-context/branch-issue-id.sh
```

The single owner of branch-to-identifier matching. It reads the current branch via `git branch --show-current`, matches it against `branchPatterns` in order, and prints capture group one of the first matching pattern on stdout. A branch matching no pattern — or no branch at all (detached HEAD, non-repository) — exits 1 and prints nothing: callers branch on the exit status and own their own user-facing messaging, and path-resolving callers rely on the silence to keep flat placement clean.

## Script: get-issue-folder-path.sh

```bash
~/.claude/skills/issue-context/get-issue-folder-path.sh [--id <identifier>]
```

Prints the `.claude-work/` folder that holds a work item's files: `<claude-work-root>[/<segment>]/<identifier>`. With `--id` the identifier is validated through `resolve-issue-id.sh`. Without `--id` the identifier is inferred through `branch-issue-id.sh`; a branch matching no pattern prints just the root (flat placement). The folder is NOT created. Errors print to stderr and exit 1.

## Breadcrumbs

`/breadcrumb` writes to a single file per issue (not a numbered sequence), so it does not use `target-path.sh`. It calls `claude-work-root.sh` to get the base directory, then writes to `<base>/issues/<ID>/breadcrumb.md` or `<base>/breadcrumb-<slug>.md`.

## History

Before the refactor in [issues/120](https://github.com/couimet/my-claude-skills/issues/120), this file contained ~118 lines of Markdown that restated the branch-parsing rules in prose, and those same rules were also inlined into `/scratchpad`, `/question`, and `/commit-msg`. The audit concluded that deterministic logic belongs in a shell script (the pattern set by `/auto-number` and `/ensure-gitignore`), not in Markdown auto-consulted for every file-creation task. This file is now a pointer to the script.
