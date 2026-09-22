---
name: tackle-pr-comment
version: 2026.09.16@ae50bfe
description: Tackle a PR comment - analyze feedback, explore code, and create implementation working document
argument-hint: <pr-comment-url> [--scratchpad]
skill-kind: composite
allowed-tools: Read, Glob, Grep, Write, AskUserQuestion, Bash(*/skills/issue-context/branch-issue-id.sh *), Bash(git diff *), Bash(gh api repos/*/*/pulls/*/reviews/*), Bash(gh api repos/*/*/pulls/comments/*), Bash(gh api repos/*/*/issues/comments/*), Bash(gh api repos/*/*/pulls/*/comments*), Bash(gh api repos/*/*/issues/*/comments*), Bash(mkdir -p *), Bash(date *), Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/issue-context/get-issue-folder-path.sh *), Bash(*/skills/issue-context/claude-work-root.sh *), Bash(*/skills/question/extract-answers.sh *), Bash(*/skills/answers-ready/find-waves.sh *), Bash(*/skills/prose-style/check-prose.sh *), Bash(*/skills/issue-context/skill-version.sh *), Bash(*/skills/answers-ready/classify-ack.sh *)
---

# Tackle PR Comment

Analyze a PR comment, explore the referenced code, and create a detailed implementation working document. This skill is for **analysis and planning only**. It does not implement changes until the user approves.

**Input:** $ARGUMENTS (a PR comment URL, optionally followed by `--scratchpad`)

This skill produces an _auxiliary_ working document. It does NOT overwrite the branch's active-plan pointer. `/finish-issue` will still treat the primary plan (from the original `/start-issue` or `/start-side-quest`) as the reference. This document is read as supplementary context.

## Step 1: Parse the URL and Fetch the Comment

Parse the URL to determine the comment type and extract IDs:

| URL Fragment              | Type                 | API Call                                              |
| ------------------------- | -------------------- | ----------------------------------------------------- |
| `#pullrequestreview-{id}` | Review               | `gh api repos/{owner}/{repo}/pulls/{pr}/reviews/{id}` |
| `#discussion_r{id}`       | Inline code comment  | `gh api repos/{owner}/{repo}/pulls/comments/{id}`     |
| `#issuecomment-{id}`      | Conversation comment | `gh api repos/{owner}/{repo}/issues/comments/{id}`    |

Extract: owner, repo, PR number, comment type, and comment ID from the URL.

## Step 2: Fetch Thread Context

### For Inline Code Comments (`discussion_r*`)

These may be part of a threaded conversation. After fetching the target comment:

1. Check if it has `in_reply_to_id` (meaning it's a reply to a top-level comment)
2. If it is a reply, fetch the top-level comment it replies to
3. Fetch all comments on the PR: `gh api repos/{owner}/{repo}/pulls/{pr}/comments`
4. Filter to find all direct replies to the top-level comment
5. Present the full thread chronologically (one level deep: top comment + direct replies)

**Note:** GitHub's REST API does not support nested threads (replies to replies). All comments in a thread are direct replies to a single top-level comment.

### For Issue Comments (`issuecomment-*`)

1. First, get the total count: `gh api repos/{owner}/{repo}/issues/{pr}/comments --jq 'length'`
2. Fetch the 5 most recent comments for context (sorted by creation time, newest first)
3. **If total > 5**: Inform the user:
   > "This PR has {N} comments. I loaded the 5 most recent for context. Would you like me to load all {N} for a holistic view?"
4. Wait for user response before proceeding if they want full context (workflow blocks until user responds)

### For Reviews (`pullrequestreview-*`)

Fetch the review directly - reviews are standalone with their body containing the full feedback.

## Step 3: Analyze and Explore Code

1. **Identify code references** in the comment(s):
   - File paths mentioned
   - Line numbers referenced
   - Function/class names discussed

2. **Explore the codebase**:
   - Read the referenced files
   - Understand the current implementation
   - Look at related code that might be affected
   - Check existing tests

3. **Understand the reviewer's concern**:
   - What is the core issue or suggestion?
   - Is this about correctness, style, performance, or architecture?
   - What outcome does the reviewer want?

## Step 4: Assess Clarity

Before creating the scratchpad, assess if the feedback is clear enough to act on:

**If unclear**: Stop and tell the user:

> "The reviewer's feedback is ambiguous. Before I create an implementation plan, we may need to ask a clarifying question. Here's what's unclear: [explain]. Would you like me to draft a clarifying question for the PR?"

**If clear**: Proceed to Step 5.

## Step 5: Create Implementation Working Document

Before drafting, restate the rules that apply to this document: hard-wrap and reference rules from `/prose-style`, and the Output Anchors block below. Then re-read the comment thread, the linked code, and any files explored in Step 3. Decide ACCEPT or IGNORE on each feedback item with the actual code in mind. The analysis is the highest-leverage artifact this skill produces.

**Grill before writing anything.** Work the analysis and action plan out in-session and run `/g2q` on it as a topic, focused on the ACCEPT/IGNORE decisions and the action-plan step ordering. Do not write a draft file first: it costs output tokens and buys nothing on the common path, where grilling raises no questions and the working document is written seconds later. It grills the draft for genuinely open ambiguities (applying the trigger predicate at the top of `/g2q`, the single source of trigger truth), creates a questions file via `/question` when it finds any, and reports whether any were raised and, when raised, whether the run is paused or complete. The report gates how the working document is created in 5a/5b:

- If grilling raised questions, create the note/scratchpad only as a pending stub (see 5a/5b): it MUST start with the banner `Production of this plan awaits answers to the questions in <absolute questions file path>, which will affect the plan.`, followed by the analysis outline, and MUST NOT contain the finalized analysis and action plan. The stub is the only written record of the reasoning while the grill is open, so the outline must carry enough of it for a later session to resume. Then continue to Step 6. A paused report (the newest wave file ends with questions held for a later wave) still counts as raised: create the stub exactly this way, since answers are pending, and Step 7 re-grills between answer waves before finalizing.
- If grilling raised nothing, create the full working document per 5a/5b, then continue to Step 6.

Choose the working-document type based on whether formal step tracking is requested:

- **Default (`/note`):** use this unless the user explicitly opted in. Produces a lightweight, freeform analysis + action plan.
- **Opt-in (`/scratchpad`):** triggered when `$ARGUMENTS` contains `--scratchpad`, or when the user's invoking message contains a natural-language opt-in phrase ("use a scratchpad", "with step tracking", "formal plan", "track steps"). Produces a scratchpad with a JSON step block (including `addresses` fields) so `/tackle-scratchpad-block` can drive execution.

Use description: `pr-{PR_NUMBER}-{COMMENT_TYPE}-{COMMENT_ID}`

Where:

- `{COMMENT_TYPE}` is: `review`, `discussion`, or `issuecomment`
- `{COMMENT_ID}` is the numeric ID from the URL (e.g., `3647271799`, `2680237139`, `987654`)

**Naming convention:** use letters (A, B, C) for feedback items in text headings. When the opt-in path applies, use `S001`, `S002` IDs for implementation steps in the JSON block. This avoids confusion when referencing "Feedback B" vs "S002".

**No new CHANGELOG entries.** The working document must never include a step that adds a new CHANGELOG entry. The current branch's existing entry for the in-flight PR may be amended to stay accurate, but no new heading or entry is created — even if the branch has no entry at all. Never draft an "Add CHANGELOG entry" step.

### 5a. Default path: `/note`

Use `/note` with the description above. When the grilling gate raised questions, create the note only as a pending stub (banner + analysis outline, no finalized plan). Otherwise the note contains (all prose, no JSON step block):

```markdown
# PR https://github.com/{owner}/{repo}/pull/{PR_NUMBER} Comment Response

Source: {FULL_PR_COMMENT_URL}

## Analysis

### Feedback A: {short title}

{Analysis of first feedback item}

Decision: [RECOMMENDED] ACCEPT | IGNORE
Reason: {brief justification. Omit if self-evident from the analysis above}

### Feedback B: {short title}

{Analysis of second feedback item}

Decision: [RECOMMENDED] ACCEPT | IGNORE
Reason: {brief justification. Omit if self-evident from the analysis above}

## Action Plan

Numbered prose steps (no fenced JSON). Each step names the feedback items it addresses (e.g. "Step 1 (addresses A, C): ...") and the specific files/functions to change. Feedback items marked IGNORE are omitted from this list.

---

When you have reviewed every decision above, send this to Claude:

/answers-ready <absolute path to this file>
```

**The decisions carry the same acknowledgment marker as a questions file, and the same hard gate.** Each `Decision:` line is written with `[RECOMMENDED]` because you chose it, not the user. The user clears the marker to acknowledge a decision, or edits the verdict outright. Step 8 refuses to implement while any marker stands, and names the feedback items still carrying one. A standing marker never means the user agreed: it means they have not looked yet, and an ACCEPT acted on unread is a change nobody approved.

### 5b. Opt-in path: `/scratchpad`

Use `/scratchpad` with the description above. When the grilling gate raised questions, create the scratchpad only as a pending stub (banner + analysis outline, no finalized plan and no JSON step block yet). Otherwise use the same sections as 5a, except `## Action Plan` is replaced with `## Implementation Plan` containing a fenced JSON step block per the `/scratchpad` Step Tracking schema. For PR-comment work:

- Omit `finish_issue_on_complete` (it is `false` by default for ad-hoc scratchpads).
- Add an `addresses` field to each step listing the feedback item letters it resolves (e.g. `"addresses": ["A", "C"]`).

Formatting: see `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.

### Output Anchors

Deliverable: a single text file containing the analysis of each feedback item and the action plan.
Length: 1 to 2 sentences per feedback item under Analysis. The user will ask for more depth or clarification if needed. Action Plan is however many steps the work actually requires. A single sentence is enough for a trivial change. Multi-feedback responses may need several steps. Each step names the feedback letters it addresses.
Format: prose sections (Analysis with per-item Decision + Reason, Action Plan) per the template above. No fenced JSON in the default `/note` path.
Scope: this comment thread's feedback only. Leave broader refactors and out-of-scope improvements out of the Action Plan.
Tone: direct, decision-first (ACCEPT or IGNORE), reviewer-facing.

**STOP HERE** - The template ends above. Always end the working document at this point, whether a full document or a pending stub. Commit messages are created separately in Step 8 (after user approval) using `/commit-msg`.

## Step 6: Report and Stop

The terminal is a receipt, not a second copy of the analysis. Print the created path, a questions path when one exists, a decision count, and one `Next:` line. Do not summarize what you found: the analysis is in the file the receipt names, and repeating it in the terminal costs the tokens twice.

```text
Created: <absolute working-document path>   # labelled "note" or "scratchpad"
Questions: <absolute questions file path>   # only when one was created
Decisions: <n> ACCEPT, <n> IGNORE
Next: <the line below that matches the state reached in Step 5>
```

The decision counts stay because they orient the reader without reproducing the reasoning. Drop even those if they do not earn their line.

**Grilling raised questions and the run is complete (pending stub created):**

```text
Next: answer the questions, then send /answers-ready <absolute questions file path>.
```

**Grilling raised questions and the run is paused (more waves may follow):**

```text
Next: answer the questions, then send /answers-ready <absolute questions file path>. The run is paused: questions remain held for a later wave, so answering this one emits the next rather than finalizing the working document.
```

**No questions raised (full working document written):**

```text
Next: review the decisions, then tell me to proceed.
```

**IMPORTANT: Do NOT start implementing changes.**

Wait for the user:

- When the grilling gate raised questions, for the answers to the questions file, then run Step 7 to finalize the working document
- Otherwise, for review of the working document and an explicit request to proceed with implementation

## Step 7: Finalize the Plan After Answers

Only reached when Step 5's grilling gate raised questions and the working document is a pending stub. `/answers-ready` owns this procedure: follow its Step 4.

This skill's specifics: the document is the analysis and action plan, the answers resolve each ACCEPT/IGNORE decision and the step ordering, the re-grill topic is the stub's outline plus every answer collected so far, and no pointer needs updating because PR-comment working documents are auxiliary. Report the finalized working-document path and STOP, matching the no-questions-raised output in Step 6.

## Step 8: Commit Message (After User Approves)

When the user approves the plan and asks to proceed:

1. **Check the decision markers first.** Every `Decision:` line in the working document must have had its `[RECOMMENDED]` marker cleared. If any still stands, stop, name the feedback items carrying one, and wait. Do not implement an ACCEPT the user has not looked at. `/answers-ready <path to the working document>` is how the user signals they are through: it classifies the file, checks the markers, and names any decision still carrying one.

2. **Ask**: "Would you like me to create a commit message file now? (The implementation plan has enough context to draft it.)"

3. **If yes**: Use `/commit-msg` to create the commit message file with these specific requirements:
   - Use `[PR feedback]` as the commit type (instead of the usual type like `[refactor]` or `[fix]`)
   - Include a `Ref: {PR_COMMENT_URL}` footer to link back to the review comment
   - Do NOT include the `Co-Authored-By:` block

4. **If any reviewer feedback was ignored**: Add an `Ignored Feedback:` section after the Benefits section. For each ignored item:
   - Briefly describe the suggestion that was not implemented
   - Include reasoning for why it was skipped (prefilled based on your recommendation if the user didn't provide explicit reasoning)
   - This ensures reviewers know the feedback wasn't missed. It was intentionally declined

5. **Then**: Proceed with implementation.

### Commit Message Format for PR Feedback

```text
[PR feedback] Short summary of what was addressed

Body explaining the change and why.

Benefits:
- Benefit 1
- Benefit 2

Ignored Feedback:
- {Suggestion that was skipped}: {Brief reasoning for why}

Ref: {PR_COMMENT_URL}
```

This allows the commit message to be drafted early (from the plan) rather than waiting until all changes are complete.

## Quality Checklist

Before finishing initial analysis (Step 6):

- [ ] Comment was fetched successfully with full thread context (if applicable)
- [ ] Working document (note or scratchpad) contains link to source PR comment
- [ ] Working document created via `/note` (default) or `/scratchpad` (opt-in). Not both
- [ ] Active-plan pointer was NOT overwritten (PR-comment scratchpads are auxiliary)
- [ ] Plan has specific file/function names
- [ ] Each step is actionable and concrete
- [ ] Action plan includes NO new CHANGELOG entry (existing branch entry may be amended only)
- [ ] Grilling ran before any file was written (Step 5) and gated the working document on the answers
- [ ] When grilling raised questions, the working document is a pending stub with the awaiting-answers banner and the full analysis and action plan is deferred
- [ ] User was informed if clarification from reviewer is needed

After user approves (Step 8):

- [ ] Asked user if they want a commit message file created
- [ ] If yes, created commit message with `[PR feedback]` type and `Ref:` footer
- [ ] If any feedback was ignored, added `Ignored Feedback:` section with reasoning
