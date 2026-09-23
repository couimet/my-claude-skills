---
name: start-issue
version: 2026.09.16@ae50bfe
description: Start working on a GitHub issue - analyze, explore codebase, and create detailed implementation plan
argument-hint: <github-issue-url> [--scratchpad]
skill-kind: composite
allowed-tools: Read, Write, Glob, Grep, AskUserQuestion, Bash(git branch --show-current), Bash(git fetch *), Bash(git checkout *), Bash(gh issue view *), Bash(gh issue edit * --add-assignee *), Bash(gh api graphql *), Bash(gh issue comment *), Bash(mkdir -p *), Bash(date *), Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/issue-context/resolve-issue-id.sh *), Bash(*/skills/issue-context/get-issue-folder-path.sh *), Bash(*/skills/issue-context/branch-issue-id.sh *), Bash(*/skills/issue-context/render-branch-template.sh *), Bash(*/skills/issue-context/claude-work-root.sh *), Bash(*/skills/issue-context/work-folder-tier.sh *), Bash(*/skills/cleanup-issue/find-obsolete-issue-dirs.sh *), Bash(*/skills/cleanup-issue/remove-issue-dir.sh *), Bash(*/skills/start-issue/update-project-status.sh *), Bash(*/skills/question/extract-answers.sh *), Bash(*/skills/answers-ready/find-waves.sh *), Bash(*/skills/prose-style/check-prose.sh *)
---

# Start Issue

Analyze a GitHub issue, explore the codebase, and create a detailed implementation plan. This skill is for **planning only**. It does not implement anything.

**Input:** $ARGUMENTS (a GitHub issue URL)

## Step 0: Clean Up Current Issue Artifacts

Run both commands as parallel tool calls:

```bash
~/.claude/skills/issue-context/branch-issue-id.sh
```

```bash
~/.claude/skills/issue-context/claude-work-root.sh
```

Use the stdout of `claude-work-root.sh` as `<base>` for all `.claude-work/` paths in this skill. See `/issue-context-internals` for the contracts of the identifier, branch, and folder scripts this skill calls.

The gate `branch-issue-id.sh` prints the current branch's work-item identifier and exits 1 with no output when the branch matches no configured pattern. On exit 1 there is no issue context: go straight to Step 1.

On exit 0, run the finder with the `<base>` resolved above:

```bash
~/.claude/skills/cleanup-issue/find-obsolete-issue-dirs.sh "<base>"
```

Each DELETABLE line has the form `DELETABLE<TAB><path><TAB><reason>`. Fewer than 5 means skip silently and go to Step 1. Five or more means present one AskUserQuestion whose text lists those paths, with two options: **Prune now**, which deletes each listed folder, and **Keep everything**, the safe default.

Only when the user picks Prune now do you need `/cleanup-issue`: it owns the delete, the confirmation wording, and the tier caveat that says what the delete will and will not reach. Until then its body is not worth the context, which is why this step reads the finder's output rather than invoking the skill to find out whether there is anything to do.

## Step 1: Fetch Issue Details and Assign

Parse `$ARGUMENTS` first: it holds the issue URL optionally followed by `--scratchpad`. If `$ARGUMENTS` contains `--scratchpad`, set the scratchpad-opt-in flag (it selects the 4a/4b path in Step 4) and strip the token so the remaining value is the issue argument, `<issue-url>`. Never pass `--scratchpad` to `gh`.

Run both commands as parallel tool calls in the same response. They are independent (one reads, one writes) and both use `<issue-url>` directly:

```bash
gh issue view "<issue-url>" --json title,body,number,state,labels,assignees,comments
```

```bash
gh issue edit "<issue-url>" --add-assignee @me
```

The assign is additive: existing assignees are preserved, not replaced. The command is idempotent (silently succeeds if you are already assigned).

**Read all comments before continuing.** If the `comments` array is non-empty, read every comment in full — treat them as equal-weight context alongside the issue body. Design discussions, CodeRabbit analysis, and follow-up decisions in comments often refine or contradict the original description.

## Step 1b: Update Project Status

After assignment, detect whether the issue belongs to any GitHub Projects V2 boards and move those project items to "In Progress" status:

```bash
~/.claude/skills/start-issue/update-project-status.sh "<owner>" "<repo>" "<issue_number>"
```

Where `<owner>` and `<repo>` are extracted from the issue URL, and `<issue_number>` is the GitHub issue number.

Continue regardless of the script's exit code, and say nothing when it prints nothing. Project status updates are additive and must never block `/start-issue`.

## Step 2: Create Feature Branch

First resolve the work-item identifier from `<issue-url>` (from Step 1):

```bash
~/.claude/skills/issue-context/resolve-issue-id.sh "<issue-url>"
```

Record its stdout as `<ID>`.

Resolve the issue folder this identifier maps to, for all `.claude-work/` paths in the remaining steps:

```bash
~/.claude/skills/issue-context/get-issue-folder-path.sh --id "<ID>"
```

Its stdout is `<folder>` (e.g., `<base>/issues/248` under the default `segment`), derived from the configured `segment`.

Render the feature branch name from the configured `branchTemplate` with the helper, which substitutes `{id}` with `<ID>` and degrades to the default `issues/{id}` when the settings template is missing or unsubstitutable:

```bash
~/.claude/skills/issue-context/render-branch-template.sh "<ID>"
```

Use its stdout as `<branch>`.

Create the feature branch from the selected base branch (`origin/main` by default, or another base branch if instructed):

```bash
git fetch origin && git checkout -b "<branch>" "<BASE_BRANCH>"
```

Where `<branch>` is the rendered template value (e.g., `issues/248`) and `<BASE_BRANCH>` is typically `origin/main`. Record the actual base branch used in the scratchpad's `Base branch:` field. It may differ in stacked-PR workflows.

## Step 3: Gather Full Context

- **Fetch parent issues**: if the issue body references a parent (e.g., "Parent Issue: #47"), fetch it to understand the broader goal and how this issue fits into the plan
- **Note child issues**: if this is a parent/epic, note child issues to understand full scope
- **Explore the codebase**: use Grep/Glob/Read to find and examine:
  - Files/functions mentioned in the issue
  - Related code that will be affected
  - Existing patterns to follow
  - Test files that will need updates
- **Check integration points**: review the project's entry points, configuration, documentation, and discoverability conventions for anything the change might affect
- **Check for project-local hooks**: if the project has a `/start-issue-hook` skill (foundation skill in the project's `.claude/skills/` directory), it is loaded as additional context automatically. Read it and incorporate whatever it specifies into the plan generated in Step 4. If no such skill exists, continue with the vanilla plan. See `/skill-hooks` for the full extension mechanism.

## Step 4: Create Implementation Plan Working Document

Before drafting the plan, re-read the issue body, any parent issue, and the files surfaced in Step 3. Think through actual file and function names, step ordering, and dependencies before writing. The plan is the highest-leverage artifact this skill produces. Treat it as such. See `/pre-write` for the think-before-writing rule. If any aspect of the plan is unclear after this review, use `/question` before writing.

**Grill before writing anything.** Work the plan out in-session and run `/g2q` on it as a topic, passing the plan you have reasoned out rather than a file. Do not write a draft file first. A draft costs output tokens to write and buys nothing on the common path, where grilling raises no questions and the real plan is written seconds later. `/g2q` grills for genuinely open ambiguities (applying the trigger predicate at its top, the single source of trigger truth), creates a questions file under the issue's `<folder>/questions/` directory (from Step 2) when it finds any, and reports whether any were raised and, when raised, whether the run is paused or complete. The report gates how the working document is created in 4a/4b:

- If grilling raised questions, create the note/scratchpad only as a pending stub (see 4a/4b): it MUST start with the banner `Production of this plan awaits answers to the questions in <absolute questions file path>, which will affect the plan.`, followed by the plan outline, and MUST NOT contain the finalized plan. The stub is the only written record of the reasoning while the grill is open, so the outline must carry enough of it for a later session to resume. Write the active-plan pointer (4c) and base-branch marker (4d) to the stub, then continue to Step 5. A paused report (the newest wave file ends with questions held for a later wave) still counts as raised: create the stub exactly this way, since answers are pending, and Step 6 re-grills between answer waves before finalizing.
- If grilling raised nothing, create the full plan note/scratchpad per 4a/4b, then continue to Step 5. Exactly one file is written on this path.

Choose the working-document type based on whether formal step tracking is requested:

- **Default (`/note`):** use this unless the user explicitly opted in. Produces a lightweight, freeform plan. Relies on you (the LLM) to self-organize execution in-session via TaskCreate/TaskUpdate.
- **Opt-in (`/scratchpad`):** triggered when the scratchpad-opt-in flag was set in Step 1 (`$ARGUMENTS` contained `--scratchpad`), or when the user's invoking message contains a natural-language opt-in phrase ("use a scratchpad", "with step tracking", "formal plan", "track steps"). Produces a scratchpad with a JSON step block so `/tackle-scratchpad-block` can drive execution.

### 4a. Default path: `/note`

Use `/note` with description `start-issue-plan`. When the grilling gate raised questions, create the note only as a pending stub (banner + plan outline, no finalized plan). Otherwise the note MUST contain these sections (all prose, no JSON step block):

```markdown
# Issue #NUMBER: Title

Base branch: <branch this was cut from (origin/main, or another branch if instructed)>
Parent: https://github.com/{owner}/{repo}/issues/{XX} (omit if no parent)

Commit model for this plan: one commit at the end covering all changes. When the work is done, call `/finish-issue` directly. Do not call `/commit-msg` first, because the PR description file doubles as the commit message body.

## Context

- Brief issue summary (1-2 sentences)
- Parent issue context: how this fits into broader plan (omit if no parent)

## Assumptions Made (omit section if none)

- "Assuming X because Y": non-obvious reasoning only

## Plan

Numbered prose steps (no fenced JSON). Each step should be commit-sized, specific (name files/functions), ordered (dependencies clear), and mention test updates where relevant.
```

### 4b. Opt-in path: `/scratchpad`

Use `/scratchpad` with description `start-issue-plan`. When the grilling gate raised questions, create the scratchpad only as a pending stub (banner + plan outline, no finalized plan and no JSON step block yet). Otherwise the scratchpad uses the same prose sections as 4a, except the `## Plan` section is replaced with `## Implementation Plan` containing a fenced JSON step block. See the `/scratchpad` Step Tracking section for the full schema. For `/start-issue` specifically: set `finish_issue_on_complete: true` at the top level, and always set each step's `status: "pending"` when planning. `/tackle-scratchpad-block` manages status transitions during execution.

### 4c. Write the active-plan pointer

After the working document is created (via either path), write the pointer file so `/finish-issue` and `/tackle-scratchpad-block` can resolve the primary plan without guessing:

**Path:** `<folder>/active-plan` (where `<folder>` is from Step 2)

Create `<folder>` before writing either pointer. Step 2 resolved it with `--id`, and under a session override or a worktree marker that names a directory nothing has created yet: `/note` and `/scratchpad` resolve with no argument, so they created `<override>/notes/` or `<override>/scratchpads/` somewhere else entirely. Only under the branch tier do the two resolutions agree, which is the one case where the directory already exists.

```bash
mkdir -p "<folder>"
```

**Contents:** the absolute path to the working document (a single line, no trailing newline required), which is what `/note` and `/scratchpad` already return, so write what they gave you without converting it. For example:

```text
/Users/you/project/.claude-work/issues/126/notes/<the-filename-/note-returned>.txt
```

Overwrite any existing pointer. Only the most recent working document is "active". When the grilling gate created a pending stub, the pointer targets the stub and stays valid after finalization (Step 6), which rewrites the same file.

### 4d. Write the base-branch marker

Record the base branch so `/rebase-issue` can later determine whether to use stacked diff-apply or normal rebase. Like the active-plan pointer in Step 4c, this marker lives in the issue folder resolved in Step 2.

**Path:** `<folder>/base-branch` (absolute path)

**Contents:** the base branch ref recorded in the plan's `Base branch:` field (a single line, no trailing newline). Examples:

```text
origin/main
```

```text
issues/186
```

Always write this file — even when the base is `origin/main`. Consistency gives `/rebase-issue` a single code path: always read the marker, always check remote existence.

Overwrite any existing marker. Only the most recent `/start-issue` invocation matters.

Formatting: see `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.

### Output Anchors

Deliverable: implementation plan note (or scratchpad, if opted in).
Length: as long as needed to name specific files and functions. Sections are typically 1 to 4 short paragraphs. The Plan list contains however many commit-sized steps the work actually requires. A trivial fix may be one step. A large refactor may be a dozen or more. Match the issue, not a number.
Format: prose sections (Context, Assumptions Made, Plan) per the template above. No fenced JSON in the default `/note` path.
Scope: planning only. Name files, functions, and test updates. Skip implementation prose.
Tone: direct, concrete, file-and-function-named. No hedging, no generic conclusions.

## Step 5: Report Status and STOP

The terminal is a receipt, not a second copy of the plan. Print the branch, the created path, a questions path when one exists, and one `Next:` line. Nothing else: no plan summary, no step list, no pointer paths. Everything a reader needs beyond the receipt is in the file the receipt names.

```text
Branch: <branch>
Created: <absolute working-document path>
Questions: <absolute questions file path>   # only when one was created
Next: <the line below that matches the state reached in Step 4>
```

**Grilling raised questions and the run is complete (pending stub created):**

```text
Next: answer the questions, then send /answers-ready <absolute questions file path>.
```

**Grilling raised questions and the run is paused (more waves may follow):**

```text
Next: answer the questions, then send /answers-ready <absolute questions file path>. The run is paused: questions remain held for a later wave, so answering this one emits the next rather than finalizing the plan.
```

The paused wording stays because the user cannot infer it from anything else on screen.

**No questions raised, full plan written - default path (note):**

```text
Next: review the plan, then tell me to go ahead.
```

The commit model is not printed. It lives in the note's header (4a), where it survives into a session that reads the plan days later.

**No questions raised, full plan written - opt-in path (scratchpad):**

```text
Next: /tackle-scratchpad-block <absolute-path-to-scratchpad> (add #S002 to pick a specific step).
```

**IMPORTANT: Do NOT proceed with implementation.**

This skill is for planning only. After reporting status:

- When the grilling gate raised questions, wait for the user to answer the questions file, then run Step 6 to finalize the plan
- Otherwise, wait for the user to review the implementation plan
- Only begin implementation when the user explicitly asks (e.g., "proceed", "start implementing", "go ahead")

## Step 6: Finalize the Plan After Answers

Only reached when Step 4's grilling gate raised questions and the working document is a pending stub. `/answers-ready` owns this procedure: follow its Step 4.

This skill's specifics: the document is the implementation plan, the answers resolve its ambiguities and any decision that became an assumption goes under `## Assumptions Made`, the re-grill topic is the stub's outline plus every answer collected so far, and the active-plan pointer (4c) already targets the file and stays valid. Report the finalized plan path and STOP, matching the no-questions-raised output in Step 5.

## Quality Checklist

Before finishing, verify:

- [ ] Feature branch built from the configured `branchTemplate` (default `issues/{id}`) was created
- [ ] Working document created via `/note` (default) or `/scratchpad` (opt-in), not both
- [ ] `<folder>` created before either pointer was written
- [ ] `<folder>/active-plan` pointer written with the absolute path to the working document
- [ ] `<folder>/base-branch` marker written with the recorded `Base branch:` ref
- [ ] Plan has specific file/function names (not "update the code")
- [ ] Each step is small enough to be one commit
- [ ] Test updates are mentioned for each step that changes behavior
- [ ] Assumptions are documented with reasoning
- [ ] Questions (if any) would genuinely change the plan if answered differently
- [ ] Grilling ran before any file was written (Step 4) and gated the working document on the answers
- [ ] When grilling raised questions, the working document is a pending stub with the awaiting-answers banner and the full plan is deferred
- [ ] Documentation and discoverability considered
- [ ] Project status update attempted (Step 1b) — silent failure is OK, but the step must not be skipped
