---
name: issue-context
version: 2026.09.08@212eab1
user-invocable: false
description: Contract for the issue-context shell scripts that resolve .claude-work/ file paths from the current git branch and from the configurable work-item settings. Referenced by name from the skills that write working files, not auto-consulted.
allowed-tools: Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/issue-context/claude-work-root.sh *), Bash(*/skills/issue-context/resolve-issue-id.sh *), Bash(*/skills/issue-context/branch-issue-id.sh *), Bash(*/skills/issue-context/get-issue-folder-path.sh *), Bash(*/skills/issue-context/render-branch-template.sh *)
---

# Issue Context

All deterministic logic for "where should this file go?" lives in the scripts. Skills that write working files call `target-path.sh`. Skills that only need the `.claude-work/` root directory call `claude-work-root.sh`.

## Script: target-path.sh

## Script contract

```bash
~/.claude/skills/issue-context/target-path.sh --type <scratchpads|questions|commit-msgs|notes> --description "<text>" [--ext txt]
```

The script resolves the work-item folder through `get-issue-folder-path.sh`. That helper reads the identifier from the current branch and applies the configured `segment`. The script then slugifies the description, names the file, creates the target directory, and prints one path on stdout.

**Four properties callers can rely on.** These four are the contract. Every other detail of the returned path belongs to the script and can change without notice. The filename format is one such detail.

1. **Absolute.** You can print the path for the user. You can use it from any working directory.
2. **Directory exists and the path is reserved.** The script creates the directory and reserves the path, so the file is already there and empty when you get it. Write over that reservation. Do not create the directory, and do not read an empty file at a returned path as a working file: it is a reservation whose caller has not written yet.
3. **Unique.** A write to this path never replaces an existing file, and two calls never hand out the same path, even when they run at the same moment. Do not check the directory first. Do not edit an earlier file instead of creating a new one.
4. **Lexicographic order equals creation order.** A byte-order sort of a directory lists the files from oldest to newest. To find the newest file that matches a pattern, take the maximum. Any caller that resolves "the most recent" file relies on this.

Placement follows the branch context. On a branch that matches a configured `branchPatterns` entry, the file goes under the work-item folder. On every other branch, the file goes to the `.claude-work/` root, under its type directory.

The next line is an example, not a specification. Read the filename format from `target-path.sh`. Do not read it from prose:

```text
/Users/x/project/.claude-work/issues/42/questions/20260909-101500-001-scope-question.txt
```

## Script: claude-work-root.sh

```bash
~/.claude/skills/issue-context/claude-work-root.sh
```

Returns the absolute path to the `.claude-work/` root directory, taking git worktrees into account. In the primary checkout `.claude-work/` lives at `--show-toplevel` (same as before). In a linked worktree (detected by comparing `--git-dir` against `--git-common-dir`), `.claude-work/` lives at the main checkout root so all worktrees share a single copy.

The script outputs an absolute path on stdout (e.g., `/Users/x/project/.claude-work`). The directory is NOT created by this script. Callers handle that.

A caller that needs only the root directory calls this script. The caller appends its own subdirectory and filename.

## Settings: issue-settings.sh

The work-item path convention is configurable through `~/.my-claude-skills/settings.json`, whose path is overridable with `MY_CLAUDE_SKILLS_CONFIG` (which must hold a full path to the file). `issue-settings.sh` locates and parses that file and exposes the result as `SETTINGS_*` globals; scripts source it rather than execute it. Any failure — missing file, malformed JSON, invalid regex in a pattern entry — writes a warning to stderr and resolves to the built-in defaults, never refusing to resolve. Keys and defaults:

- `segment` — directory name under the `.claude-work/` root that holds work-item folders; default `issues`. An explicit empty string omits the directory.
- `branchPatterns` — ordered EREs matched against branch names; first match wins and capture group one is the identifier. Defaults to the five-row list in the settings file: `^issues/([0-9]+)[-_]`, `^issues/([0-9]+)$`, `^issues/([A-Za-z][A-Za-z0-9]*-[0-9]+)`, `^issues/(.+)$`, `^([A-Za-z][A-Za-z0-9]*-[0-9]+)`.
- `branchTemplate` — branch name built from an identifier; default `issues/{id}`. Paired with `branchPatterns`: a rendered branch must parse back under the configured patterns to the identifier it was built from, so a template-only override whose output they cannot re-parse is rejected (see render-branch-template.sh).
- `urlPatterns` — ordered EREs matched against tracker URLs; first match wins and capture group one is the identifier. Defaults to `/issues/([0-9]+)`, `/browse/([A-Za-z][A-Za-z0-9]+-[0-9]+)`.
- `identifierCase` — case a resolved identifier is folded to: `upper` (the default), `lower`, or `preserve`. Only tracker-key-shaped identifiers (`^[A-Za-z][A-Za-z0-9]*-[0-9]+$`) are folded, so numeric identifiers and free-form slugs pass through untouched. An absent key means `upper`, which unlike every other key here is not the pre-existing behavior: case-preserving resolution is the defect this key closes. An unrecognized value warns and falls back to `upper`; an empty value takes the default silently, the same as an absent key.
- `version` — settings schema version; default `1`.

## Script: resolve-issue-id.sh

```bash
~/.claude/skills/issue-context/resolve-issue-id.sh <URL-or-identifier>
```

Resolves a single argument to a canonical work-item identifier. A value with a URL shape (it contains a scheme like `https://`) is matched against `urlPatterns` in order; the first pattern that matches supplies the identifier as its first capture group. A value without a URL shape is a bare identifier. Both paths fold the result to the configured `identifierCase` before printing it, so the same ticket reached through a tracker URL and through a bare key resolves to one identifier and therefore one folder. Every identifier — bare or captured from a URL pattern — must be usable as one path segment and one branch segment, which rejects empty values, `.` and `..`, anything containing an internal `/`, leading/trailing dots or slashes, and any whitespace. A URL-shaped value matching no pattern, an unsafe identifier, or the wrong argument count prints an error to stderr and exits 1 — refusing is safer than inventing an identifier. Output is a single line on stdout.

## Script: branch-issue-id.sh

```bash
~/.claude/skills/issue-context/branch-issue-id.sh
```

Resolves the current branch's work-item identifier through the shared matcher in issue-settings.sh, which applies the configured `branchPatterns` in order, folds capture group one to the configured `identifierCase`, and prints the first result usable as one path segment. The matcher is shared with render-branch-template.sh, so a rendered branch and a recognized branch always resolve to the same identifier. A captured identifier must be usable as one path segment — a branch like `issues/foo/bar` could otherwise hand callers a value that builds a path outside the work-item folder — so an empty or unsafe capture is treated as a non-match and the next pattern is tried. A branch matching no pattern — or no branch at all (detached HEAD, non-repository) — exits 1 and prints nothing: callers branch on the exit status and own their own user-facing messaging, and path-resolving callers rely on the silence to keep flat placement clean.

## Script: get-issue-folder-path.sh

```bash
~/.claude/skills/issue-context/get-issue-folder-path.sh [--id <identifier>]
```

Prints the `.claude-work/` folder that holds a work item's files: `<claude-work-root>[/<segment>]/<identifier>`. With `--id` the identifier is validated through `resolve-issue-id.sh`. Without `--id` the identifier is inferred through `branch-issue-id.sh`; a branch matching no pattern prints just the root (flat placement). The folder is NOT created. Errors print to stderr and exit 1.

## Script: render-branch-template.sh

```bash
~/.claude/skills/issue-context/render-branch-template.sh <identifier>
```

Prints the configured `branchTemplate` with its `{id}` placeholder replaced by the given identifier, which is folded to the configured `identifierCase` first: the matcher that re-parses the rendered branch folds too, so rendering a raw `proj-1234` unfolded would build a branch that parses back to `PROJ-1234` and fail the round-trip check below with an error naming the wrong cause. Falls back to the default `issues/{id}` (substituted) when the template is empty or contains no `{id}` placeholder, so branch creation and `branch-issue-id.sh`'s branch matching share one config path and degrade to the default together. The rendered branch is parsed back through the same shared matcher (issue-settings.sh) and must resolve to the identifier it was built from: `branchTemplate` and `branchPatterns` are a paired configuration, and a rendered branch the configured patterns cannot re-parse — or parse to a different id — is rejected with an error before any branch is created, since the caller would otherwise build a branch the gate treats as non-work. An unsafe identifier prints an error to stderr and exits 1.
