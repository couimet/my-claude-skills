---
name: cleanup-issue
version: 2026.02.26.2@5bab05c
description: Delete an issue's working directory (.claude-work/issues/<ID>/) after confirming with the user via interactive prompt
argument-hint: [optional: issue-number]
allowed-tools: Read, Glob, AskUserQuestion, Bash(git branch --show-current), Bash(rm -rf .claude-work/issues/*)
---

# Cleanup Issue

Remove an issue's working directory after the work is done. Uses `AskUserQuestion` to confirm before deleting anything.

**Input:** $ARGUMENTS (optional issue number; if omitted, detects from branch)

## Step 1: Determine Issue ID

If `$ARGUMENTS` is provided and is a number, use it as the issue ID.

Otherwise, detect from the current branch using `/issue-context` branch detection rules:

```bash
git branch --show-current
```

Extract the issue ID from `issues/<ID>` pattern. If the branch doesn't match `issues/*`, and no argument was provided, STOP:

- Print: "No issue context found. Provide an issue number: `/cleanup-issue 42`"

## Step 2: Check for Issue Directory

Check if the issue directory exists:

```text
.claude-work/issues/<ID>/
```

Use Glob to list contents:

```text
Glob(pattern="**/*", path=".claude-work/issues/<ID>")
```

**If directory doesn't exist or is empty:**

- Print: "No working directory found for issue #`<ID>` at `.claude-work/issues/<ID>/`."
- Skip to Step 5

## Step 3: Confirm Deletion

Use `AskUserQuestion` to prompt for confirmation. Include the full directory path and file list in the question so the user knows exactly what will be deleted.

```text
AskUserQuestion(
  question: "Delete working directory for issue #<ID>?\n\n.claude-work/issues/<ID>/ contains:\n<file list from Step 2>\n\nThis is irreversible.",
  options: [
    { label: "Delete", description: "Remove .claude-work/issues/<ID>/ and all contents" },
    { label: "Keep", description: "Leave everything untouched" }
  ]
)
```

## Step 4: Act on Answer

- **Delete** → proceed to deletion
- **Keep** → print "Keeping `.claude-work/issues/<ID>/` untouched." and STOP

### Delete

```bash
rm -rf .claude-work/issues/<ID>
```

Print:

```text
Cleaned up .claude-work/issues/<ID>/ — all working files removed.
```

## Step 5: Check for Side-Quest Artifacts

Regardless of whether the issue directory existed or was deleted, scan for orphaned side-quest files in the `.claude-work/` root:

```text
Glob(pattern="breadcrumb-*.md", path=".claude-work")
Glob(pattern="scratchpads/*side-quest*", path=".claude-work")
Glob(pattern="commit-msgs/*side-quest*", path=".claude-work")
```

**If side-quest artifacts are found:**

- Print the list of found files
- Print: "These side-quest files may be from completed work. Clean them up manually if no longer needed."

**If no side-quest artifacts found:** skip silently.

## Prose Style

Format all prose output per the `/prose-style` skill conventions.
