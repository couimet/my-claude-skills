---
name: issue-context
version: 2026.09.10@486eb33
user-invocable: false
description: Contract for the issue-context shell scripts that resolve working-file paths from the current session's folder override, the current git branch, and the configurable work-item settings. Referenced by name from the skills that write working files, not auto-consulted.
allowed-tools: Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/issue-context/claude-work-root.sh *), Bash(*/skills/issue-context/resolve-issue-id.sh *), Bash(*/skills/issue-context/branch-issue-id.sh *), Bash(*/skills/issue-context/get-issue-folder-path.sh *), Bash(*/skills/issue-context/render-branch-template.sh *), Bash(*/skills/issue-context/set-work-folder.sh *), Bash(*/skills/issue-context/work-folder-tier.sh *)
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
3. **Unique.** The script never hands out a path that is already taken, and two calls never hand out the same path, even when they run at the same moment. The only file your write replaces is the empty reservation property 2 describes. Do not check the directory first. Do not edit an earlier file instead of creating a new one.
4. **Lexicographic order equals creation order.** A byte-order sort of a directory lists the files from oldest to newest. To find the newest file that matches a pattern, take the maximum. Any caller that resolves "the most recent" file relies on this.

Placement has two levels, resolved in this order. First, the current session's folder override, when one is set and passes the checks below. Second, the branch context: on a branch matching a configured `branchPatterns` entry the file goes under the work-item folder, and on every other branch it goes to the `.claude-work/` root, under its type directory. A caller writes a working file the same way either way; the override is invisible to it.

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

Prints the folder that holds a work item's files. Without `--id` it walks three tiers in order: the session override, then this worktree's `CLAUDE_WORK_FOLDER` marker, then the branch-derived `<claude-work-root>[/<segment>]/<identifier>` with the identifier inferred through `branch-issue-id.sh`; a branch matching no pattern and no override prints just the root (flat placement). With `--id` the identifier is validated through `resolve-issue-id.sh`, the session override is never consulted, and the marker is honoured as `<marker>/<identifier>` with no segment between. The folder is NOT created. Errors print to stderr and exit 1.

**Stdout is exactly one line, and it is a path.** Callers capture it with command substitution and then create the directory it names, so a status message on stdout would be captured as part of the path and turned into a directory named after the message. Every report this script makes goes to stderr for that reason, and the rule is written here so nobody reintroduces the fault.

The script reports the folder it chose on stderr on every run, and reports separately any override it found and did not use. Without that second line, an override silently ignored looks exactly like never having set one.

## The session folder override

A session can name the folder its working files go to, instead of letting the branch decide. This exists because a repository organised by topic has no way to express placement through a branch name.

The override is written by `set-work-folder.sh`:

```bash
~/.claude/skills/issue-context/set-work-folder.sh <folder> [name]
~/.claude/skills/issue-context/set-work-folder.sh --clear
~/.claude/skills/issue-context/set-work-folder.sh --worktree <folder>
~/.claude/skills/issue-context/set-work-folder.sh --clear --worktree
```

`<folder>` must be an absolute path to an existing directory; a relative path and a missing directory are both refused rather than warned about or created, because a typo at write time is read immediately. `[name]` is a cosmetic label for the stored file's name, taken from the argument, else from the `name` in the session's job state file, else omitted. Nothing is ever looked up by the label, so it may go stale. The folder is not required to be inside any repository, and nothing checks that it is: an override may name any existing absolute directory. `--clear` removes the override and succeeds when none is set.

The `--worktree` forms write and remove this worktree's marker instead of this session's override. They need no session id, because a marker belongs to a checkout rather than to a conversation, and they refuse to run outside a git repository, where there is no worktree root for the file to sit at.

## Script: work-folder-tier.sh

```bash
~/.claude/skills/issue-context/work-folder-tier.sh
```

Prints exactly one token, `session`, `worktree`, or `branch`, naming the tier that resolution would use right now. A caller cannot work this out from a resolved path, and checking whether the marker file exists is wrong because the session tier outranks it. A skill that deletes a work item's directory asks this so its confirmation can say what the delete will and will not reach. The tier order lives in `work-folder.sh`, sourced by this script and by `get-issue-folder-path.sh`, so the two cannot disagree.

**Three tiers, in order.** The session override comes first, then this worktree's marker, then branch-derived placement. The session tier is deliberate and ephemeral, so it beats the standing one; both beat a default inferred from a branch name. The order lives in `work-folder.sh` and nowhere else.

**Where the worktree marker lives.** A file named `CLAUDE_WORK_FOLDER` at the worktree root, holding one line: an absolute path, or a path whose leading `~/` expands against `$HOME`. It sits at the worktree root rather than under `.claude-work/` because that directory is shared across a repository's worktrees, and two worktrees must be able to point at different folders or at none. It is not gitignored on purpose: it shows in `git status` every day, which is what makes a standing override one you cannot forget you set. It is not JSON, so a missing `jq` cannot take out this tier as well as the session tier.

**Where the override lives.** One JSON file per session, under a `sessions/` directory beside the settings file, named for the session id and the optional label. `MY_CLAUDE_SKILLS_CONFIG` therefore relocates the settings and the sessions together. The document carries a `version`, the `folder` (the only field routing reads), the `session_id`, the `slug`, a `written_at` stamp, and a best-effort `written_by` record of which agent set it. A reader ignores any field it does not recognise, so a later version can add fields safely. The file is written atomically, because two agents in one session can write at the same moment and a half-written document must never be readable. The session id is spelled straight into that filename, so a session id that could not be a filename component is refused by the writer and read as no override at all, rather than naming a file beside the sessions directory instead of inside it.

**A session keeps exactly one file.** A second write replaces the first in place, even under a different label. Two files describing one session cannot be told apart, so the reader refuses a multiple match instead of picking one.

**When an override is refused.** Each of these falls back to the next tier and says so on stderr: the folder does not exist, the path is not absolute, more than one file matches the session, the file is unreadable or malformed, the file carries a version the reader does not know, or `jq` is absent. A marker is refused on the same terms, plus when it is empty or unreadable. Refusing to resolve a path at all would block an unrelated call for a reason that has nothing to do with it, so the resolver never fails on a bad override.

**The override is session-wide.** Subagents launched through the Agent tool run in the same process and inherit the session identity, so one agent setting a folder changes it for its parent and its siblings too. The `written_by` record is what makes an unexpected change traceable afterwards.

**Identity is the session, never the process.** The process backing a conversation is replaced underneath it, and every environment variable dies at that replacement, while the session id survives it. That is why this is a file keyed on the session id and not an exported variable, including as a seed for the file.

## Script: render-branch-template.sh

```bash
~/.claude/skills/issue-context/render-branch-template.sh <identifier>
```

Prints the configured `branchTemplate` with its `{id}` placeholder replaced by the given identifier, which is folded to the configured `identifierCase` first: the matcher that re-parses the rendered branch folds too, so rendering a raw `proj-1234` unfolded would build a branch that parses back to `PROJ-1234` and fail the round-trip check below with an error naming the wrong cause. Falls back to the default `issues/{id}` (substituted) when the template is empty or contains no `{id}` placeholder, so branch creation and `branch-issue-id.sh`'s branch matching share one config path and degrade to the default together. The rendered branch is parsed back through the same shared matcher (issue-settings.sh) and must resolve to the identifier it was built from: `branchTemplate` and `branchPatterns` are a paired configuration, and a rendered branch the configured patterns cannot re-parse — or parse to a different id — is rejected with an error before any branch is created, since the caller would otherwise build a branch the gate treats as non-work. An unsafe identifier prints an error to stderr and exits 1.
