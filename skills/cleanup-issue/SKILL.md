---
name: cleanup-issue
description: Delete an issue's working directory (.claude-work/issues/<ID>/) after confirming with the user via /question
argument-hint: [optional: issue-number]
allowed-tools: Read, Write, Glob, Bash(git branch --show-current), Bash(rm -rf *)
---

# Cleanup Issue

Remove an issue's working directory after the work is done. Uses `/question` to confirm before deleting anything.

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

```
.claude-work/issues/<ID>/
```

Use Glob to list contents:

```
Glob(pattern="**/*", path=".claude-work/issues/<ID>")
```

**If directory doesn't exist or is empty:**

- Print: "No working directory found for issue #`<ID>` at `.claude-work/issues/<ID>/`."
- STOP

## Step 3: Confirm Deletion

Use `/question` to create a confirmation file. This ensures the user sees exactly what will be deleted and makes a deliberate choice.

Create a questions file with topic `cleanup-issue-<ID>`:

```text
# Cleanup Issue #<ID>

## Q001: Delete the working directory for issue #<ID>?

Context: The directory .claude-work/issues/<ID>/ contains the following files:

<list all files found by Glob in Step 2, indented>

This action is irreversible — all scratchpads, questions, commit messages, and breadcrumbs for this issue will be permanently deleted.

Options:
A) Delete - Remove .claude-work/issues/<ID>/ and all contents
B) Keep - Leave everything untouched

Recommendation: A - The issue work is complete and these files are no longer needed.

A001: [RECOMMENDED] A

---
```

Print ONLY the questions file path and wait for the user to answer.

## Step 4: Read Answer and Act

Read the questions file back. Check `A001`:

- **`A` or `Delete`** → proceed to deletion
- **`B` or `Keep`** → print "Keeping `.claude-work/issues/<ID>/` untouched." and STOP
- **Still `[RECOMMENDED]`** → print "Please review and acknowledge the answer in the questions file before proceeding." and STOP

### Delete

```bash
rm -rf .claude-work/issues/<ID>
```

Print:

```text
Cleaned up .claude-work/issues/<ID>/ — all working files removed.
```

## Step 5: Check for Side-Quest Artifacts

After handling the issue directory (or if it didn't exist), scan for orphaned side-quest files in the `.claude-work/` root:

```
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
