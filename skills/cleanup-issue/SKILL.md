---
name: cleanup-issue
version: 2026.06.25@7353cfe
description: Delete an issue's working directory (.claude-work/issues/<ID>/) after confirming with the user via interactive prompt
argument-hint: [optional: issue-number]
allowed-tools: Read, Glob, AskUserQuestion, Bash(git branch --show-current), Bash(*/skills/cleanup-issue/remove-issue-dir.sh *), Bash(*/skills/issue-context/claude-work-root.sh *)
---

# Cleanup Issue

Remove an issue's working directory after the work is done. Uses `AskUserQuestion` to confirm before deleting anything.

**Input:** $ARGUMENTS (optional issue number; if omitted, detects from branch)

## Step 1: Determine Issue ID

If `$ARGUMENTS` is provided and is a number, use it as the issue ID.

Otherwise, detect from the current branch:

```bash
git branch --show-current
```

Extract the issue ID from the `issues/<ID>` pattern (numeric prefix before the first `-`/`_` when present, otherwise the full segment after `issues/`). If the branch doesn't match `issues/*`, and no argument was provided, STOP:

- Print: "No issue context found. Provide an issue number: `/cleanup-issue 42`"

### Validate the ID

The `remove-issue-dir.sh` script enforces ID validation internally (regex `^[A-Za-z0-9][A-Za-z0-9._-]*$`, rejects `.` and `..`). The ID extracted above is passed verbatim to the script in Step 4; if invalid, the script exits with a clear error and performs no deletion. No separate prose validation step is needed.

## Step 2: Check for Issue Directory

First, resolve the `.claude-work/` root directory:

```bash
~/.claude/skills/issue-context/claude-work-root.sh
```

Use the stdout as `<base>` for all `.claude-work/` paths below. This script automatically detects git worktrees and returns the shared location.

Check if the issue directory exists:

```text
<base>/issues/<ID>/
```

Use Glob to list contents:

```text
Glob(pattern="**/*", path="<base>/issues/<ID>")
```

**If directory doesn't exist or is empty:**

- Print: "No working directory found for issue #`<ID>` at `<base>/issues/<ID>/`."
- Skip to Step 5

## Step 3: Confirm Deletion

Use `AskUserQuestion` to prompt for confirmation. Include the full directory path and file list in the question so the user knows exactly what will be deleted.

```text
AskUserQuestion(
  question: "Delete working directory for issue #<ID>?\n\n<base>/issues/<ID>/ contains:\n<file list from Step 2>\n\nThis is irreversible.",
  options: [
    { label: "Delete", description: "Remove <base>/issues/<ID>/ and all contents" },
    { label: "Keep", description: "Leave everything untouched" }
  ]
)
```

## Step 4: Act on Answer

- **Delete** → proceed to deletion
- **Keep** → print "Keeping `<base>/issues/<ID>/` untouched." and STOP

### Delete

Only reached if the user selected Delete in Step 3. The `remove-issue-dir.sh` script validates the ID, verifies the base path, checks that the resolved physical path stays under `<base>/issues/`, and performs the removal. No raw `rm -rf` is used.

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

## Formatting

See `/prose-style` for hard-wrap rules.
