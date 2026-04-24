---
name: start-side-quest
version: 2026.04.24@2423d79
description: Start a side-quest branch for orthogonal improvements discovered while working on an issue
argument-hint: <description | path/to/file.ts#L10-L20> [--scratchpad]
allowed-tools: Read, Write, Glob, Grep, Bash(git fetch *), Bash(git checkout *), Bash(git branch --show-current), Bash(git status *), Bash(git stash *), Bash(*/skills/auto-number/auto-number.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Start Side-Quest

Start a "side-quest" — a focused branch for orthogonal improvements discovered while working on another issue. Side-quests keep the main issue branch clean and focused.

**Input:** $ARGUMENTS

This can be:

- A description of the side-quest (e.g., "BookmarksStore API improvements")
- A code reference (e.g., src/bookmarks/BookmarksStore.ts#L216-L254)
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

The base branch for the side-quest is the branch that was active when `/start-side-quest` was invoked (captured in Step 1). This is typically `origin/main` but may be any branch — for example, when working in a stack of PRs.

```bash
git fetch origin
git checkout -b side-quest/<slug> <base-branch>
```

Branch naming pattern: `side-quest/<descriptive-slug>`

Examples:

- `side-quest/bookmarks-store-api-improvements`
- `side-quest/fix-result-type-usage`
- `side-quest/cleanup-test-mocks`

## Step 3: Create Implementation Working Document

Choose the working-document type based on whether formal step tracking is requested:

- **Default (`/note`):** use this unless the user explicitly opted in. Produces a lightweight, freeform plan. Relies on you (the LLM) to self-organize execution in-session.
- **Opt-in (`/scratchpad`):** triggered when `$ARGUMENTS` contains `--scratchpad`, or when the user's invoking message contains a natural-language opt-in phrase ("use a scratchpad", "with step tracking", "formal plan", "track steps"). Produces a scratchpad with a JSON step block so `/tackle-scratchpad-block` can drive execution.

Side-quest branches don't match `issues/*`, so the working document lands in the flat `.claude-work/notes/` (default) or `.claude-work/scratchpads/` (opt-in) directory.

### 3a. Default path — `/note`

Use `/note` with description `side-quest-<slug>`. The note MUST contain (all prose — no JSON step block):

````markdown
# Side-Quest: <Title>

Base branch: <branch this was cut from — origin/main, issues/XXX, or another branch>

## Goal

1-2 sentences explaining what improvement this side-quest delivers.

## Plan

Numbered prose steps (no fenced JSON). Each step commit-sized and specific.
````

### 3b. Opt-in path — `/scratchpad`

Use `/scratchpad` with description `side-quest-<slug>`. Same sections as 3a, except `## Plan` is replaced with `## Implementation Plan` containing a fenced JSON step block per the `/scratchpad` Step Tracking schema. Set `finish_issue_on_complete: true` at the top level.

### 3c. Write the active-plan pointer

After the working document is created (via either path), write the pointer file so `/finish-issue` and `/tackle-scratchpad-block` can resolve the primary plan:

**Path:** `.claude-work/active-plan-<slug>`

**Contents:** the project-root-relative path to the working document, for example:

```text
.claude-work/notes/20260424-143022-side-quest-cleanup-test-mocks.txt
```

Overwrite any existing pointer with the same slug.

Formatting: see `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.

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
- .claude-work/notes/<file>.txt (implementation plan — default path)
  OR .claude-work/scratchpads/<file>.txt (if --scratchpad)
- .claude-work/active-plan-<slug> (pointer to the working document)
- .claude-work/questions/<file>.txt (if questions needed)

Stash: <stash message if applicable>

---

Ready to implement. When done:
1. Commit your changes
2. Run `/finish-issue` to verify, generate PR description, and wrap up
3. Return to parent: git checkout <parent-branch>
   (run `git stash pop` only if changes were stashed)
```

**IMPORTANT: Do NOT proceed with implementation.**

This skill sets up the side-quest context. Wait for user to:

- Review the plan
- Explicitly ask to implement (e.g., "proceed", "implement", "go ahead")

## Quality Checklist

Before finishing, verify:

- [ ] Current work stashed (if on a work branch with changes)
- [ ] Side-quest branch created from `<base-branch>`
- [ ] Working document created via `/note` (default) or `/scratchpad` (opt-in) — not both
- [ ] `.claude-work/active-plan-<slug>` pointer written with the project-root-relative path to the working document
- [ ] Plan has specific file/change details
- [ ] Parent branch noted for easy return

## Example Invocations

- Default path: produces a `/note`

User: `/start-side-quest src/types/Result.ts#L45-L60`

- Reads the linked code for context
- Derives side-quest scope from what the code suggests

User: `/start-side-quest cleanup ExtensionResult usage in test mocks --scratchpad`

- Creates `side-quest/cleanup-extensionresult-usage-in-test-mocks`
- Opt-in path: produces a `/scratchpad` with JSON step tracking so `/tackle-scratchpad-block` can drive execution
