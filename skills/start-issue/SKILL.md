---
name: start-issue
description: Start working on a GitHub issue - analyze, explore codebase, and create detailed implementation plan
argument-hint: <github-issue-url>
allowed-tools: Read, Write, Glob, Grep, Bash(git fetch *), Bash(git checkout *), Bash(gh issue view *)
---

# Start Issue

Analyze a GitHub issue, explore the codebase, and create a detailed implementation plan. This skill is for **planning only** — it does not implement anything.

**Input:** $ARGUMENTS (a GitHub issue URL)

## Step 1: Fetch Issue Details

```bash
gh issue view $ARGUMENTS --json title,body,number,state,labels
```

## Step 2: Create Feature Branch

Create a feature branch from the latest remote main:

```bash
git fetch origin && git checkout -b issues/<NUMBER> origin/main
```

Where `<NUMBER>` is the GitHub issue number (e.g., `issues/223`).

## Step 3: Gather Full Context

- **Fetch parent issues** — if the issue body references a parent (e.g., "Parent Issue: #47"), fetch it to understand the broader goal and how this issue fits into the plan
- **Note child issues** — if this is a parent/epic, note child issues to understand full scope
- **Explore the codebase** — use Grep/Glob/Read to find and examine:
  - Files/functions mentioned in the issue
  - Related code that will be affected
  - Existing patterns to follow
  - Test files that will need updates
- **Check integration points** — review the project's entry points, configuration, documentation, and discoverability conventions for anything the change might affect

## Step 4: Create Implementation Plan Scratchpad

Use `/scratchpad` to create a working document. The `/issue-context` skill will handle directory placement based on the branch.

The scratchpad for issues MUST contain these sections:

```markdown
# Issue #NUMBER: Title

Parent: #XX (if applicable)
Type/Priority/Scope: from labels

## Context

- Brief issue summary (1-2 sentences)
- Parent issue context: how this fits into broader plan (if applicable)
- Key insight from codebase exploration that shapes the implementation

## Implementation Plan

Numbered steps that are:

- **Commit-sized** — each step could be a single commit or small PR
- **Specific** — reference exact files, functions, types by name
- **Ordered** — dependencies between steps are clear
- **Testable** — each step should mention what tests to add/update

Steps are embedded as a fenced JSON block (see `/scratchpad` Step Tracking section for full schema):

```json
{
  "steps": [
    {
      "id": "S001",
      "title": "<brief description>",
      "status": "pending",
      "done_when": "<concrete criteria for this step>",
      "depends_on": [],
      "files": ["src/types/<filename>.ts", "src/types/index.ts"],
      "tasks": [
        "Add <TypeName> interface to src/types/<filename>.ts",
        "Export from src/types/index.ts"
      ]
    },
    {
      "id": "S002",
      "title": "<brief description>",
      "status": "pending",
      "done_when": "<concrete criteria for this step>",
      "depends_on": ["S001"],
      "files": ["src/<path>/<filename>.ts"],
      "tasks": [
        "Modify <functionName>() in src/<path>/<filename>.ts",
        "Update return type, add new parameters"
      ]
    },
    {
      "id": "S003",
      "title": "<brief description>",
      "status": "pending",
      "done_when": "All new functions have test coverage, tests pass",
      "depends_on": ["S002"],
      "files": ["src/<path>/__tests__/<filename>.test.ts"],
      "tasks": [
        "Add tests in src/<path>/__tests__/<filename>.test.ts",
        "Cover happy path, edge cases, error conditions"
      ]
    }
  ]
}
```

Note: Always set `"status": "pending"` when planning — `/tackle-scratchpad-block` manages status transitions during execution.

## Assumptions Made

List any reasonable defaults assumed to avoid blocking on minor decisions:

- "Assuming X because Y" — document reasoning

## Files to Modify

Bulleted list of all files that will be touched, grouped by step.

## Documentation & Discoverability

Check the project's documentation and discoverability conventions. Common touchpoints:

- [ ] CHANGELOG entry (under appropriate version section)
- [ ] README update (if new command, setting, or feature)
- [ ] Any project-specific integration points (entry points, config, menus, keybindings)
- [ ] Unreleased markers on new README content (if project uses trunk-based documentation)

## Acceptance Criteria

Checklist from the issue (copy verbatim if provided).
```

Format all code references per the `/code-ref` skill conventions.

Format all prose output per the `/prose-style` skill conventions.

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

Print the branch name and paths of any created scratchpad/questions files.

**IMPORTANT: Do NOT proceed with implementation.**

This skill is for planning only. After reporting status:

- Wait for the user to review the implementation plan
- Only begin implementation when the user explicitly asks (e.g., "proceed", "start implementing", "go ahead")

## Quality Checklist

Before finishing, verify:

- [ ] Feature branch `issues/<NUMBER>` was created
- [ ] Implementation plan has specific file/function names (not "update the code")
- [ ] Each step is small enough to be one commit
- [ ] Test updates are mentioned for each step that changes behavior
- [ ] Assumptions are documented with reasoning
- [ ] Questions (if any) would genuinely change the plan if answered differently
- [ ] Documentation and discoverability considered
