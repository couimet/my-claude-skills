---
name: start-side-quest
description: Start a side-quest branch for orthogonal improvements discovered while working on an issue
argument-hint: <description | path/to/file.ts#L10-L20>
allowed-tools: Read, Write, Glob, Grep, Bash(git fetch *), Bash(git checkout *), Bash(git branch --show-current), Bash(git status *), Bash(git stash *)
---

# Start Side-Quest

Start a "side-quest" — a focused branch for orthogonal improvements discovered while working on another issue. Side-quests keep the main issue branch clean and focused.

**Input:** $ARGUMENTS

This can be:

- A description of the side-quest (e.g., "BookmarksStore API improvements")
- A code reference per `/code-ref` format (e.g., `src/bookmarks/BookmarksStore.ts#L216-L254`)
- Both combined

## Step 1: Capture Current State

First, determine the current branch and its state:

```bash
git branch --show-current
git status --porcelain
```

If on an `issues/*` or `side-quest/*` branch with uncommitted changes:

- Note the parent branch name for return context
- Stash the changes with a descriptive message

```bash
git stash push -m "WIP: <parent-branch> - paused for side-quest"
```

## Step 2: Create Side-Quest Branch

Derive a slug from the description (lowercase, hyphens, no special chars).

```bash
git fetch origin
git checkout -b side-quest/<slug> origin/main
```

Branch naming pattern: `side-quest/<descriptive-slug>`

Examples:

- `side-quest/bookmarks-store-api-improvements`
- `side-quest/fix-result-type-usage`
- `side-quest/cleanup-test-mocks`

## Step 3: Create Implementation Scratchpad

Use `/scratchpad` to create a working document. Since side-quest branches don't match `issues/*`, the scratchpad will be placed in the flat `.scratchpads/` directory per `/issue-context` rules.

Use description: `side-quest-<slug>`

The scratchpad MUST contain:

```
# Side-Quest: <Title>

Parent branch: <issues/XXX or main> (branch to return to after)
Origin: <what triggered this - code review, refactoring discovery, etc.>

## Goal

1-2 sentences explaining what improvement this side-quest delivers.

## Changes

Numbered list of specific changes:

1. <File>: <what changes>
2. <File>: <what changes>

## Why Split This Out

Brief explanation of why this is orthogonal to the parent work:

- Doesn't block the parent issue
- Can be reviewed/merged independently
- Keeps parent PR focused

## Acceptance Criteria

- [ ] All tests pass
- [ ] Changes are minimal and focused
- [ ] Ready for independent PR
```

Format all code references per the `/code-ref` skill conventions.

## Step 4: Create Questions File (Only If Necessary)

**Only create questions for decisions that would fundamentally change the approach.**

If questions are needed, use `/question` to create a questions file and gather user input.

## Step 5: Report Status and STOP

Print a summary:

```text
=== Side-Quest Started ===

Branch: side-quest/<slug>
Parent: <original branch> (stashed if had changes)

Files created:
- .scratchpads/<file>.txt (implementation plan)
- .claude-questions/<file>.txt (if questions needed)

Stash: <stash message if applicable>

---

Ready to implement. When done:
1. Run the project's test suite
2. Create commit message with /commit-msg
3. Commit and create PR
4. Return to parent: git checkout <parent-branch>
   (run `git stash pop` only if changes were stashed)
```

**IMPORTANT: Do NOT proceed with implementation.**

This skill sets up the side-quest context. Wait for user to:

- Review the plan
- Explicitly ask to implement (e.g., "proceed", "implement", "go ahead")

## Quality Checklist

Before finishing, verify:

- [ ] Current work stashed (if on a work branch with changes)
- [ ] Side-quest branch created from origin/main
- [ ] Scratchpad has specific file/change details
- [ ] Parent branch noted for easy return

## Example Invocations

User: `/start-side-quest BookmarksStore.remove() should return deleted bookmark`

- Creates `side-quest/bookmarksstore-remove-returns-bookmark`

User: `/start-side-quest src/types/Result.ts#L45-L60`

- Reads the linked code for context
- Derives side-quest scope from what the code suggests

User: `/start-side-quest cleanup ExtensionResult usage in test mocks`

- Creates `side-quest/cleanup-extensionresult-test-mocks`
