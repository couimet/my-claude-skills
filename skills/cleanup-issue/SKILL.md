---
name: cleanup-issue
version: 2026.09.21@73231a2
description: Delete an issue's working directory under .claude-work/ after confirming with the user via interactive prompt
argument-hint: '[issue-id] | --sweep'
allowed-tools: Read, Glob, AskUserQuestion, Bash(*/skills/cleanup-issue/find-obsolete-issue-dirs.sh *), Bash(*/skills/cleanup-issue/remove-issue-dir.sh *), Bash(*/skills/issue-context/branch-issue-id.sh *), Bash(*/skills/issue-context/get-issue-folder-path.sh *), Bash(*/skills/issue-context/claude-work-root.sh *), Bash(*/skills/issue-context/work-folder-tier.sh *)
---

# Cleanup Issue

Remove an issue's working directory after the work is done. Uses `AskUserQuestion` to confirm before deleting anything.

**Input:** $ARGUMENTS (optional issue id — a number, tracker key, or slug — or `--sweep`. If omitted, detects from branch)

## Step 1: Determine Issue ID

If `$ARGUMENTS` is provided, use it as the issue ID. It may be numeric (`42`), a tracker key (`PROJ-123`), or a slug; `remove-issue-dir.sh` validates it before deleting.

Otherwise, resolve the identifier from the current branch via `branch-issue-id.sh`:

```bash
~/.claude/skills/issue-context/branch-issue-id.sh
```

- **Exit 0** — the printed identifier (e.g., on `issues/42` it prints `42`) is the issue ID.
- **Exit 1** — no identifier was resolved, and no argument was provided. STOP:

- Print: "No issue context found. Provide an issue ID: `/cleanup-issue 42`"

### Validate the ID

The `remove-issue-dir.sh` script enforces ID validation internally (regex `^[A-Za-z0-9][A-Za-z0-9._-]*$`, rejects `.` and `..`, and refuses the reserved category names). The ID resolved above is passed verbatim to the script in Step 4. If invalid, the script exits with a clear error and performs no deletion. No separate prose validation step is needed.

## Step 2: Check for Issue Directory

First, resolve the `.claude-work/` root directory (sweep mode takes it as its `<base>`):

```bash
~/.claude/skills/issue-context/claude-work-root.sh
```

Use the stdout as `<base>`. This script automatically detects git worktrees and returns the shared location.

Then resolve the issue's working directory from the ID. Under the branch tier the resolver builds `<base>/<segment>/<identifier>` from the configured `segment` (defaulting to `<base>/issues/<ID>`; an empty segment omits the directory), and under a worktree marker it returns `<marker>/<identifier>` with no segment between. Take what it prints rather than assembling either form:

```bash
~/.claude/skills/issue-context/get-issue-folder-path.sh --id "<ID>"
```

Use its stdout as `<folder>`.

Then ask which tier named that folder, because it changes what a delete can reach. Ask in the `--id` form, matching the resolution just performed: a bare call would answer for a no-argument resolution, and with a session override and a marker both set it would report `session` while `<folder>` came from the marker.

```bash
~/.claude/skills/issue-context/work-folder-tier.sh --id "<ID>"
```

Record its stdout as `<tier>`. It prints `worktree` or `branch`; the `--id` form never prints `session`, because naming a work item bypasses the session override.

Use Glob to list contents:

```text
Glob(pattern="**/*", path="<folder>")
```

**If directory doesn't exist or is empty:**

- Print: "No working directory found for issue #`<ID>` at `<folder>`."
- Skip to Step 5

## Step 3: Confirm Deletion

**If `<tier>` is `worktree`:** this worktree points its working files at a folder named by `CLAUDE_WORK_FOLDER`, and that placement is flat. Notes, questions, scratchpads, and commit messages for every work item sit together in `<marker>/notes/` and its siblings, so `<folder>` holds only what the `--id` callers put there: the `active-plan` and `base-branch` pointers, `last-finish-issue`, and the breadcrumb. Say so in the confirmation below, naming what goes and what stays, so nobody reads a completed cleanup as having removed the work item's files. The other two tiers need no such line: under them `<folder>` is the work item's whole directory.

Use `AskUserQuestion` to prompt for confirmation. Include the full directory path and file list in the question so the user knows exactly what the script will delete.

```text
AskUserQuestion(
  question: "Delete working directory for issue #<ID>?\n\n<folder> contains:\n<file list from Step 2>\n\nThis is irreversible.",
  options: [
    { label: "Delete", description: "Remove <folder> and all contents" },
    { label: "Keep", description: "Leave everything untouched" }
  ]
)
```

## Step 4: Act on Answer

- **Delete** → proceed to deletion
- **Keep** → print "Keeping `<folder>` untouched." and STOP

### Delete

Only reached if the user selected Delete in Step 3. Pass `<folder>` from Step 2 verbatim: that is the path the user was shown and agreed to, and it is the only way the delete reaches the same directory the confirmation named under every tier. The script validates the ID, refuses a folder whose last component is not that ID, refuses one that resolves through a symlink to somewhere else, and performs the removal. No raw `rm -rf` is used.

```bash
~/.claude/skills/cleanup-issue/remove-issue-dir.sh "<folder>" --id "<ID>"
```

The script prints the removed path on stdout. Report that path to the user in the form that matches `<tier>` from Step 2. Under the worktree tier the folder held only the pointers and the breadcrumb, so the unconditional line would claim more than the delete did.

**If `<tier>` is `worktree`:**

```text
Cleaned up <stdout>/. The plan pointers and the breadcrumb are gone. This work item's notes, questions, scratchpads, and commit messages sit flat under the worktree's folder and remain.
```

**Otherwise:**

```text
Cleaned up <stdout>/. All working files removed.
```

## Step 5: Check for Side-Quest Artifacts

Regardless of whether the issue directory existed or was deleted, scan for orphaned side-quest files. They are not under `<base>`: `/start-side-quest` writes them through a no-argument resolution, so they follow a session folder or a worktree marker when one is set. Resolve that root the same way it did, and record the stdout as `<sq-root>`:

```bash
~/.claude/skills/issue-context/get-issue-folder-path.sh
```

```text
Glob(pattern="breadcrumb-*.md", path="<sq-root>")
Glob(pattern="scratchpads/*side-quest*", path="<sq-root>")
Glob(pattern="commit-msgs/*side-quest*", path="<sq-root>")
```

**If side-quest artifacts are found:**

- Print the list of found files
- Print: "These side-quest files may be from completed work. Clean them up manually if no longer needed."

**If no side-quest artifacts found:** skip silently.

## Sweep Mode (--sweep)

When `$ARGUMENTS` is `--sweep`, skip the single-folder Steps 1-4 and follow this section instead.

### Sweep Step 1: Resolve the Base Directory

Resolve the `.claude-work/` root directory:

```bash
~/.claude/skills/issue-context/claude-work-root.sh
```

Use the stdout as `<base>`.

### Sweep Step 2: Find Obsolete Folders

Run the sweep script:

```bash
~/.claude/skills/cleanup-issue/find-obsolete-issue-dirs.sh "<base>"
```

The script prints one line per deletable folder on stdout:

```text
DELETABLE<TAB><absolute path><TAB><reason>
```

It also prints one line per skipped folder:

```text
Skipped: <name> (not a valid work-item identifier, not checked)
```

Display all DELETABLE lines (path plus reason) and all Skipped lines to the user. If the script exits 1 with an F001 or F002 error, show the error message and STOP.

**If there are no DELETABLE lines:** print "No obsolete issue working folders found." and STOP.

### Sweep Step 3: Confirm Deletion

Use `AskUserQuestion` to prompt for confirmation. List every deletable folder path with its reason:

```text
AskUserQuestion(
  question: "Delete N obsolete issue working folders?\n\n<path> - <reason>\n<path> - <reason>\n\nThis is irreversible.",
  options: [
    { label: "Delete all N folders", description: "Remove each listed folder via remove-issue-dir.sh" },
    { label: "Keep everything", description: "Delete nothing and leave all folders untouched" }
  ]
)
```

### Sweep Step 4: Act on Answer

- **Delete all N folders** → proceed to deletion
- **Keep everything** → print "Keeping all obsolete issue folders untouched." and STOP

### Sweep Delete

Only reached if the user selected Delete all N folders in Sweep Step 3. For each listed path, run the removal script once per folder, passing the DELETABLE line's path verbatim, where `<ID>` is the folder name (the last segment of that path):

```bash
~/.claude/skills/cleanup-issue/remove-issue-dir.sh "<path>" --id "<ID>"
```

The script prints the removed path on stdout. Report each removed path to the user:

```text
Cleaned up <stdout>/. All working files removed.
```

### Sweep Step 5: Check for Side-Quest Artifacts

Perform the side-quest artifact scan from the single-folder Step 5 (resolve `<sq-root>` with the no-argument `get-issue-folder-path.sh`, Glob for `breadcrumb-*.md`, `scratchpads/*side-quest*`, and `commit-msgs/*side-quest*` in it, and report findings the same way).

Note: `/start-issue` Step 0 also offers pruning automatically when 5 or more obsolete folders accumulate. This manual `--sweep` mode always shows the full list.

## Formatting

See `/prose-style` for hard-wrap rules.
