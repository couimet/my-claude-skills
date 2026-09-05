---
name: cleanup-issue
version: 2026.09.03@a8dc4ea
description: Delete an issue's working directory under .claude-work/ after confirming with the user via interactive prompt
argument-hint: [optional: issue-number | --sweep]
allowed-tools: Read, Glob, AskUserQuestion, Bash(*/skills/cleanup-issue/find-obsolete-issue-dirs.sh *), Bash(*/skills/cleanup-issue/remove-issue-dir.sh *), Bash(*/skills/issue-context/branch-issue-id.sh *), Bash(*/skills/issue-context/get-issue-folder-path.sh *), Bash(*/skills/issue-context/claude-work-root.sh *)
---

# Cleanup Issue

Remove an issue's working directory after the work is done. Uses `AskUserQuestion` to confirm before deleting anything.

**Input:** $ARGUMENTS (optional issue number, or `--sweep`. If omitted, detects from branch)

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

The `remove-issue-dir.sh` script enforces ID validation internally (regex `^[A-Za-z0-9][A-Za-z0-9._-]*$`, rejects `.` and `..`). The ID resolved above is passed verbatim to the script in Step 4. If invalid, the script exits with a clear error and performs no deletion. No separate prose validation step is needed.

## Step 2: Check for Issue Directory

First, resolve the `.claude-work/` root directory (the removal call in Step 4 and sweep mode take it as their `<base>`):

```bash
~/.claude/skills/issue-context/claude-work-root.sh
```

Use the stdout as `<base>`. This script automatically detects git worktrees and returns the shared location.

Then resolve the issue's working directory from the ID (this honors the configured `segment` and branch-template layout, defaulting to `<base>/issues/<ID>`):

```bash
~/.claude/skills/issue-context/get-issue-folder-path.sh --id <ID>
```

Use its stdout as `<folder>`.

Use Glob to list contents:

```text
Glob(pattern="**/*", path="<folder>")
```

**If directory doesn't exist or is empty:**

- Print: "No working directory found for issue #`<ID>` at `<folder>`."
- Skip to Step 5

## Step 3: Confirm Deletion

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

Only reached if the user selected Delete in Step 3. The `remove-issue-dir.sh` script validates the ID, verifies the base path, checks that the resolved physical path stays under the configured segment directory (under `<base>` itself when the segment is empty), and performs the removal. No raw `rm -rf` is used.

```bash
~/.claude/skills/cleanup-issue/remove-issue-dir.sh <base> <ID>
```

The script prints the removed path on stdout. Report that path to the user:

```text
Cleaned up <stdout>/. All working files removed.
```

## Step 5: Check for Side-Quest Artifacts

Regardless of whether the issue directory existed or was deleted, scan for orphaned side-quest files in the `.claude-work/` root (using `<base>` from Step 2):

```text
Glob(pattern="breadcrumb-*.md", path="<base>")
Glob(pattern="scratchpads/*side-quest*", path="<base>")
Glob(pattern="commit-msgs/*side-quest*", path="<base>")
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
~/.claude/skills/cleanup-issue/find-obsolete-issue-dirs.sh <base>
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

Only reached if the user selected Delete all N folders in Sweep Step 3. For each listed path, run the removal script once per folder, where `<ID>` is the folder name (the last segment of the path):

```bash
~/.claude/skills/cleanup-issue/remove-issue-dir.sh <base> <ID>
```

The script prints the removed path on stdout. Report each removed path to the user:

```text
Cleaned up <stdout>/. All working files removed.
```

### Sweep Step 5: Check for Side-Quest Artifacts

Perform the side-quest artifact scan from the single-folder Step 5 (Glob for `breadcrumb-*.md`, `scratchpads/*side-quest*`, and `commit-msgs/*side-quest*` in `<base>` and report findings the same way).

Note: `/start-issue` Step 0 also offers pruning automatically when 5 or more obsolete folders accumulate. This manual `--sweep` mode always shows the full list.

## Formatting

See `/prose-style` for hard-wrap rules.
