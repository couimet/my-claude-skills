---
name: start-issue
version: 2026.04.24@24888a2
description: Start working on a GitHub issue - analyze, explore codebase, and create detailed implementation plan
argument-hint: <github-issue-url> [--scratchpad]
allowed-tools: Read, Write, Glob, Grep, Bash(git fetch *), Bash(git checkout *), Bash(gh issue view *), Bash(gh issue edit * --add-assignee *), Bash(*/skills/auto-number/auto-number.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Start Issue

Analyze a GitHub issue, explore the codebase, and create a detailed implementation plan. This skill is for **planning only** — it does not implement anything.

**Input:** $ARGUMENTS (a GitHub issue URL)

## Step 0: Clean Up Current Issue Artifacts

Before starting new work, run `git branch --show-current` to detect whether the current branch is `issues/<ID>`. If so, extract the ID (numeric prefix before the first `-`/`_`, or the full segment after `issues/`) and use `Glob(pattern="*", path=".claude-work/issues/<ID>")` to check whether the issue's working directory has contents. If the directory exists and has files, invoke `/cleanup-issue` to offer cleanup of that specific directory. Other issue directories are left untouched — the user may return to them later.

**If no issue context on the current branch, or the directory doesn't exist or is empty:** proceed directly to Step 1.

## Step 1: Fetch Issue Details and Assign

Run both commands as parallel tool calls in the same response — they are independent (one reads, one writes) and both use the input URL directly:

```bash
gh issue view $ARGUMENTS --json title,body,number,state,labels,assignees
```

```bash
gh issue edit $ARGUMENTS --add-assignee @me
```

The assign is additive — existing assignees are preserved, not replaced. The command is idempotent (silently succeeds if you are already assigned).

## Step 2: Create Feature Branch

Create a feature branch from the selected base branch (`origin/main` by default, or another base branch if instructed):

```bash
git fetch origin && git checkout -b issues/<NUMBER> <BASE_BRANCH>
```

Where `<NUMBER>` is the GitHub issue number (e.g., `issues/223`) and `<BASE_BRANCH>` is typically `origin/main`. Record the actual base branch used in the scratchpad's `Base branch:` field — it may differ in stacked-PR workflows.

## Step 3: Gather Full Context

- **Fetch parent issues** — if the issue body references a parent (e.g., "Parent Issue: #47"), fetch it to understand the broader goal and how this issue fits into the plan
- **Note child issues** — if this is a parent/epic, note child issues to understand full scope
- **Explore the codebase** — use Grep/Glob/Read to find and examine:
  - Files/functions mentioned in the issue
  - Related code that will be affected
  - Existing patterns to follow
  - Test files that will need updates
- **Check integration points** — review the project's entry points, configuration, documentation, and discoverability conventions for anything the change might affect

## Step 4: Create Implementation Plan Working Document

Choose the working-document type based on whether formal step tracking is requested:

- **Default (`/note`):** use this unless the user explicitly opted in. Produces a lightweight, freeform plan. Relies on you (the LLM) to self-organize execution in-session via TaskCreate/TaskUpdate.
- **Opt-in (`/scratchpad`):** triggered when `$ARGUMENTS` contains `--scratchpad`, or when the user's invoking message contains a natural-language opt-in phrase ("use a scratchpad", "with step tracking", "formal plan", "track steps"). Produces a scratchpad with a JSON step block so `/tackle-scratchpad-block` can drive execution.

### 4a. Default path — `/note`

Use `/note` with description `start-issue-plan`. The note MUST contain these sections (all prose — no JSON step block):

````markdown
# Issue #NUMBER: Title

Base branch: <branch this was cut from — origin/main, or another branch if instructed>
Parent: https://github.com/{owner}/{repo}/issues/{XX} (omit if no parent)

## Context

- Brief issue summary (1-2 sentences)
- Parent issue context: how this fits into broader plan (omit if no parent)

## Assumptions Made (omit section if none)

- "Assuming X because Y" — non-obvious reasoning only

## Plan

Numbered prose steps (no fenced JSON). Each step should be commit-sized, specific (name files/functions), ordered (dependencies clear), and mention test updates where relevant.
````

### 4b. Opt-in path — `/scratchpad`

Use `/scratchpad` with description `start-issue-plan`. The scratchpad uses the same prose sections as 4a, except the `## Plan` section is replaced with `## Implementation Plan` containing a fenced JSON step block. See the `/scratchpad` Step Tracking section for the full schema. For `/start-issue` specifically: set `finish_issue_on_complete: true` at the top level, and always set each step's `status: "pending"` when planning — `/tackle-scratchpad-block` manages status transitions during execution.

### 4c. Write the active-plan pointer

After the working document is created (via either path), write the pointer file so `/finish-issue` and `/tackle-scratchpad-block` can resolve the primary plan without guessing:

**Path:** `.claude-work/issues/<NUMBER>/active-plan`

**Contents:** the project-root-relative path to the working document (a single line, no trailing newline required), for example:

```text
.claude-work/issues/126/notes/20260424-143022-start-issue-plan.txt
```

Overwrite any existing pointer — only the most recent working document is "active".

Formatting: see `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.

## Step 5: Create Questions File (Only If Necessary)

**Only create questions for decisions that would FUNDAMENTALLY change the implementation plan.**

Do NOT ask questions about:

- Minor choices with clear best practices (assume the better option)
- Decisions where the codebase already establishes a clear, consistent pattern to follow
- Information you can verify by reading code or documentation rather than asking

DO ask questions about:

- Architectural decisions with no clear winner
- User-facing behavior where preference matters
- Scope clarification when requirements are ambiguous

If questions are needed, use `/question` to create a questions file. Add a `**Plan impact:**` line after the `Recommendation:` in each question to explain which steps would change based on the answer.

## Step 6: Report Status and STOP

Print the branch name, the working-document path, the active-plan pointer path, and any questions file path. Then print a "Next" line that matches the path taken in Step 4:

**Default path (note):**

```text
Next: review the plan, then ask me to proceed with the first step (e.g. "start S1" or just "go ahead").
I will self-organize execution using the note as reference.
Commit model: one commit at the end covering all changes. When done, call /finish-issue directly —
do NOT call /commit-msg first. The PR description file doubles as the commit message body.
```

**Opt-in path (scratchpad):**

```text
Next: use `/tackle-scratchpad-block` to execute steps one at a time.
Example: /tackle-scratchpad-block <path-to-scratchpad>
(auto-selects first pending, unblocked step)
If multiple pending, unblocked steps exist, specify which one:
  /tackle-scratchpad-block <path-to-scratchpad>#S002
```

**IMPORTANT: Do NOT proceed with implementation.**

This skill is for planning only. After reporting status:

- Wait for the user to review the implementation plan
- Only begin implementation when the user explicitly asks (e.g., "proceed", "start implementing", "go ahead")

## Quality Checklist

Before finishing, verify:

- [ ] Feature branch `issues/<NUMBER>` was created
- [ ] Working document created via `/note` (default) or `/scratchpad` (opt-in) — not both
- [ ] `.claude-work/issues/<NUMBER>/active-plan` pointer written with the project-root-relative path to the working document
- [ ] Plan has specific file/function names (not "update the code")
- [ ] Each step is small enough to be one commit
- [ ] Test updates are mentioned for each step that changes behavior
- [ ] Assumptions are documented with reasoning
- [ ] Questions (if any) would genuinely change the plan if answered differently
- [ ] Documentation and discoverability considered
