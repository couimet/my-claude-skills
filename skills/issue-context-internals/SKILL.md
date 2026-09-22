---
name: issue-context-internals
user-invocable: false
description: Contract for the issue-context scripts beyond path resolution - identifier resolution, branch matching, work-item folder resolution, branch-name rendering, the work-folder tier, and the settings file. Referenced by name from the skills that need one of them.
allowed-tools: Bash(*/skills/issue-context/resolve-issue-id.sh *), Bash(*/skills/issue-context/branch-issue-id.sh *), Bash(*/skills/issue-context/get-issue-folder-path.sh *), Bash(*/skills/issue-context/render-branch-template.sh *), Bash(*/skills/issue-context/set-work-folder.sh *), Bash(*/skills/issue-context/work-folder-tier.sh *)
---

# Issue Context Internals

Contracts for the scripts a caller reaches for when it needs more than a working-file path. A skill that only writes a working file never needs this file. ADR 003 and ADR 004 carry the rationale behind every decision recorded here.

## Script: resolve-issue-id.sh

```bash
~/.claude/skills/issue-context/resolve-issue-id.sh <URL-or-identifier>
```

Resolves one argument to a canonical work-item identifier. A URL-shaped value (it contains a scheme) is matched against the configured `urlPatterns` in order, and the first match supplies the identifier from capture group one. A value without a URL shape is a bare identifier. Both fold to the configured `identifierCase`, so the same ticket reached through a URL and through a bare key resolves to one identifier and therefore one folder.

Every identifier must work as one path segment and one branch segment, which rejects empty values, `.` and `..`, an internal `/`, leading or trailing dots and slashes, and any whitespace. A URL matching no pattern, an unsafe identifier, or the wrong argument count prints an error to stderr and exits 1: refusing is safer than inventing an identifier. Output is a single line on stdout.

## Script: branch-issue-id.sh

```bash
~/.claude/skills/issue-context/branch-issue-id.sh
```

Prints the current branch's work-item identifier, applying the configured `branchPatterns` in order and folding capture group one to the configured `identifierCase`. A captured identifier must work as one path segment, so an empty or unsafe capture is treated as a non-match and the next pattern is tried.

A branch matching no pattern, and no branch at all (detached HEAD, non-repository), exits 1 and prints nothing. Callers branch on the exit status and own their user-facing messaging, and path-resolving callers rely on the silence to keep flat placement clean.

## Script: get-issue-folder-path.sh

```bash
~/.claude/skills/issue-context/get-issue-folder-path.sh [--id <identifier>]
```

Prints the folder that holds a work item's files. Without `--id` it walks the three tiers in order: the session override, this worktree's `CLAUDE_WORK_FOLDER` marker, then branch-derived placement, printing just the root when the branch matches no pattern. With `--id` the identifier is validated, **the session override is never consulted**, and the marker is honoured as `<marker>/<identifier>` with no segment between. Naming a work item is an explicit request that an ambient session setting must not retarget.

The folder is NOT created. Errors print to stderr and exit 1.

**Stdout is exactly one line, and it is a path.** Callers capture it with command substitution and then create the directory it names, so a status message on stdout would become a directory named after the message. Every report goes to stderr for that reason, including the folder chosen and any override found and not used.

## Script: render-branch-template.sh

```bash
~/.claude/skills/issue-context/render-branch-template.sh <identifier>
```

Prints the configured `branchTemplate` with `{id}` replaced by the identifier, folded to the configured `identifierCase` first. Falls back to the default `issues/{id}` when the template is empty or carries no `{id}`. The rendered branch is parsed back through the same matcher and must resolve to the identifier it was built from: `branchTemplate` and `branchPatterns` are a paired configuration, and a rendered branch the patterns cannot re-parse is rejected before any branch is created. An unsafe identifier errors to stderr and exits 1.

## Script: work-folder-tier.sh

```bash
~/.claude/skills/issue-context/work-folder-tier.sh
```

Prints exactly one token, `session`, `worktree`, or `branch`, naming the tier resolution would use right now. A caller cannot work this out from a resolved path, and checking whether the marker file exists is wrong because the session tier outranks it. A skill that deletes a work item's directory asks this so its confirmation can say what the delete will and will not reach.

## Script: set-work-folder.sh

```bash
~/.claude/skills/issue-context/set-work-folder.sh <folder> [name]
~/.claude/skills/issue-context/set-work-folder.sh --clear
~/.claude/skills/issue-context/set-work-folder.sh --worktree <folder>
~/.claude/skills/issue-context/set-work-folder.sh --clear --worktree
```

Writes or removes this session's folder override. `<folder>` must be an absolute path to an existing directory; a relative path and a missing directory are both refused rather than created. `[name]` is a cosmetic label for the stored file's name and is never looked up, so it may go stale. The folder need not sit inside any repository.

The `--worktree` forms write and remove this worktree's marker instead of the session override. They need no session id, because a marker belongs to a checkout rather than a conversation, and they refuse to run outside a git repository.

A session keeps exactly one override file; a second write replaces the first, even under a different label. Every refusal falls back to the next tier and says so on stderr: a folder that is gone, a non-absolute path, more than one file matching the session, an unreadable or malformed file, an unknown version, or a missing `jq`. A marker is refused on the same terms, plus when it is empty or unreadable.

## Settings: issue-settings.sh

The path convention is configurable through `~/.my-claude-skills/settings.json`, overridable with `MY_CLAUDE_SKILLS_CONFIG` (a full path to the file). `issue-settings.sh` locates and parses it and exposes `SETTINGS_*` globals; scripts source it rather than execute it. Any failure writes a warning to stderr and resolves to the built-in defaults, never refusing to resolve. Keys:

- `segment` — directory under the `.claude-work/` root holding work-item folders; default `issues`. An explicit empty string omits the directory.
- `branchPatterns` — ordered EREs matched against branch names; first match wins, capture group one is the identifier.
- `branchTemplate` — branch name built from an identifier; default `issues/{id}`. Paired with `branchPatterns`.
- `urlPatterns` — ordered EREs matched against tracker URLs; first match wins, capture group one is the identifier.
- `identifierCase` — `upper` (default), `lower`, or `preserve`. Only tracker-key-shaped identifiers are folded, so numeric identifiers and free-form slugs pass through untouched. An unrecognized value warns and falls back to `upper`.
- `version` — settings schema version; default `1`.
