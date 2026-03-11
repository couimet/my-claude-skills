---
name: tackle-scratchpad-block
version: 2026.03.05.3@76c24ce
description: Execute steps from a scratchpad block and create commit message
argument-hint: <path/to/scratchpad.txt [#S00N | S00N | #L10-L20]>
allowed-tools: Read, Write, Edit, Bash(*), Glob, Grep
---

# Tackle Scratchpad Block

Execute a specific block of implementation steps from a scratchpad file, then create a commit message for review.

**Note on `Bash(*)` permission:** This skill intentionally uses unrestricted Bash access because it executes arbitrary implementation steps and test suites from user-authored scratchpad content. Other skills use allowlisted commands for their specific workflows. Users should review scratchpad content before invoking this skill.

**Input:** $ARGUMENTS (a code reference to scratchpad lines, e.g. `.claude-work/issues/70/scratchpads/0001-plan.txt#L25-L67` or `path/to/plan.txt#S003`)

## Step 1: Read the Target Block

Parse the argument to determine the invocation form, then locate the target step.

**If the argument contains `#L`** (e.g., `path/to/plan.txt#L10-L20`):
Line-range form. Read those exact lines from the file. This is the existing behaviour and the power-user escape hatch for re-running or overriding a step.

**If the argument contains `#S`** (e.g., `path/to/plan.txt#S003`):
Step-ID form (preferred). Extract the ID after `#S` (e.g., `S003`), read the full scratchpad, and locate the step whose `"id"` field matches exactly.

**If the argument ends with a space followed by a token matching `S\d+`** (e.g., `path/to/plan.txt S003`):
Space-separated step-ID form. Equivalent to the `#S` form; useful in environments where `#` in arguments is awkward. Locate the step by `"id"` in the JSON block.

**If the argument is a bare file path** (no `#` fragment, no trailing step ID):
Auto-select form. Read the full scratchpad, find all steps in the JSON block where `"status"` is `"pending"` and every entry in `"depends_on"` resolves to a step with `"status": "done"`.

- If exactly one candidate exists: proceed with it.
- If multiple candidates exist: list them and STOP. Wait for the user to pick one.
- If none exist: report "All steps are done or blocked." and STOP.

**If the reference doesn't resolve** (file not found, step ID not in JSON, lines don't exist, or content isn't actionable steps): STOP immediately and report the issue. Do not attempt to guess, search for alternatives, or infer intent.

### Check Step Status

After reading the step, parse the `"status"` field from the JSON:

- **`"done"`** → Warn the user: "This step is already done. Re-execute anyway?" Wait for confirmation.
- **`"blocked"`** → Read the `"depends_on"` array and check if the blocking steps have `"status": "done"` in the scratchpad's JSON block. If they do, proceed (the block is resolved). If not, warn: "This step depends on S00N which is not yet done." Wait for confirmation.
- **`"in_progress"`** → Warn the user: "This step is in_progress, possibly from an interrupted run. Continue?" Wait for confirmation.
- **`"pending"`** → proceed normally.

## Step 2: Understand the Context

Read the full scratchpad to understand:

- The overall goal/issue being addressed
- Parent issue context (if noted)
- Files to modify (from "Files to Modify" section if present)

Note: User controls execution order. Do not verify or block based on previous steps.

## Step 3: Assess Clarity

Before executing, assess if the steps are clear enough:

**If unclear**: Use `/question` to create a questions file and gather user input before proceeding.

**If clear**: Proceed to Step 4.

## Step 4: Mark In-Progress and Execute

Before executing, update the step's status in the scratchpad's JSON block:

```json
"id": "S002",
"title": "Implement handler",
"status": "in_progress",
```

Use the Edit tool to replace `"status": "pending"` (or `"status": "blocked"`) with `"status": "in_progress"`. Include the `"id"` and `"title"` fields in the old_string for Edit uniqueness.

Then perform the implementation work as specified in the selected lines:

- Make code changes
- Add/update tests as needed
- Fix any issues that arise

### Test Execution

Run the project's test suite after making changes.

**Exception**: Skip tests only if the scratchpad block explicitly says not to run them for this step.

## Step 5: Mark Done and Wrap Up

After successful execution and passing tests, update the step's status in the scratchpad's JSON block:

```json
"id": "S002",
"title": "Implement handler",
"status": "done",
```

Use the Edit tool to replace `"status": "in_progress"` with `"status": "done"`. Include the `"id"` and `"title"` fields in the old_string for Edit uniqueness.

**If tests fail or execution is incomplete**, leave the step as `"in_progress"` — do NOT mark it `"done"`.

### Completion Check

After marking the step done, check two conditions in the scratchpad's JSON block:

1. All steps have `"status": "done"`
2. The top-level field `"finish_issue_on_complete": true` is present

Count the total number of steps in the `"steps"` array (regardless of status) to determine the branch:

**If both conditions are true AND the scratchpad has more than one step:**

Create a `/commit-msg` file for this step first (as described below), then invoke `/finish-issue`. Print:

```text
All steps complete (finish_issue_on_complete: true) — invoking /finish-issue
```

**If both conditions are true AND the scratchpad has exactly one step:**

Invoke `/finish-issue` directly — no commit message file needed. Print:

```text
All steps complete (finish_issue_on_complete: true) — invoking /finish-issue
```

**Otherwise** (any step still pending/in_progress/blocked, OR the field is absent or false): create a commit message file as below.

Create a **NEW** commit message file for this block in all cases except a single-step scratchpad that triggers `/finish-issue`. Never reuse commit message files from previous steps.

Use `/commit-msg` to create the commit message file.

Include context from:

- The scratchpad's goal/issue number
- What was implemented in this block

**Do NOT reference the scratchpad file path** in the commit message — it's an ephemeral local file that doesn't exist on GitHub.

## Step 6: Report Status and STOP

Print:

1. Summary of changes made
2. Files modified
3. Test results (pass/fail count)
4. Either:
   - **All steps done + `finish_issue_on_complete: true` + multi-step scratchpad:** Commit message file path, then PR description path from `/finish-issue`
   - **All steps done + `finish_issue_on_complete: true` + single-step scratchpad:** `/finish-issue` was invoked — no commit message file
   - **Otherwise:** Commit message file path

**IMPORTANT: Do NOT run `git commit`.**

Wait for user to:

- Review the changes
- Review the commit message or the finish-issue output (if all steps done and `finish_issue_on_complete: true`)
- Manually commit when ready

## Quality Checklist

Before finishing:

- [ ] All steps in the target block were executed
- [ ] Tests pass (unless scratchpad explicitly skipped them)
- [ ] NEW commit message file created with clear "why" context (skipped only for single-step scratchpads when `finish_issue_on_complete: true` triggers `/finish-issue`)
- [ ] Changes align with scratchpad's stated goal
- [ ] No unrelated changes included
