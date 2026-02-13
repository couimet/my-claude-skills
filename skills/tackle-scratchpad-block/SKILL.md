---
name: tackle-scratchpad-block
description: Execute steps from a scratchpad block and create commit message
argument-hint: <path/to/scratchpad.txt#L10-L20>
allowed-tools: Read, Write, Edit, Bash(*), Glob, Grep
---

# Tackle Scratchpad Block

Execute a specific block of implementation steps from a scratchpad file, then create a commit message for review.

**Note on `Bash(*)` permission:** This skill intentionally uses unrestricted Bash access because it executes arbitrary implementation steps and test suites from user-authored scratchpad content. Other skills use allowlisted commands for their specific workflows. Users should review scratchpad content before invoking this skill.

**Input:** $ARGUMENTS (a code reference to scratchpad lines, per `/code-ref` format)

## Step 1: Read the Target Block

Read the lines specified by the code reference to get the step(s) to execute.

**If the reference doesn't resolve** (file not found, lines don't exist, or content isn't actionable steps): STOP immediately and report the issue. Do not attempt to guess, search for alternatives, or infer intent.

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

## Step 4: Execute the Steps

Perform the implementation work as specified in the selected lines:

- Make code changes
- Add/update tests as needed
- Fix any issues that arise

### Test Execution

Run the project's test suite after making changes.

**Exception**: Skip tests only if the scratchpad block explicitly says not to run them for this step.

## Step 5: Create Commit Message File

**IMPORTANT**: Always create a NEW commit message file for this block. Never reuse commit message files from previous steps.

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
4. Commit message file path

**IMPORTANT: Do NOT run `git commit`.**

Wait for user to:

- Review the changes
- Review the commit message
- Manually commit when ready

## Quality Checklist

Before finishing:

- [ ] All steps in the target block were executed
- [ ] Tests pass (unless scratchpad explicitly skipped them)
- [ ] NEW commit message file created with clear "why" context
- [ ] Changes align with scratchpad's stated goal
- [ ] No unrelated changes included
