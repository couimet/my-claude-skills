---
name: tackle-pr-comment
version: 2026.04.22@0161f71
description: Tackle a PR comment - analyze feedback, explore code, and create implementation working document
argument-hint: <pr-comment-url> [--scratchpad]
allowed-tools: Read, Glob, Grep, Write, Bash(gh api repos/*/*/pulls/*/reviews/*), Bash(gh api repos/*/*/pulls/comments/*), Bash(gh api repos/*/*/issues/comments/*), Bash(gh api repos/*/*/pulls/*/comments*), Bash(gh api repos/*/*/issues/*/comments*), Bash(*/skills/auto-number/auto-number.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Tackle PR Comment

Analyze a PR comment, explore the referenced code, and create a detailed implementation working document. This skill is for **analysis and planning only** — it does not implement changes until the user approves.

**Input:** $ARGUMENTS (a PR comment URL, optionally followed by `--scratchpad`)

This skill produces an *auxiliary* working document — it does NOT overwrite the branch's active-plan pointer. `/finish-issue` will still treat the primary plan (from the original `/start-issue` or `/start-side-quest`) as the reference; this document is read as supplementary context.

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

Choose the working-document type based on whether formal step tracking is requested:

- **Default (`/note`):** use this unless the user explicitly opted in. Produces a lightweight, freeform analysis + action plan.
- **Opt-in (`/scratchpad`):** triggered when `$ARGUMENTS` contains `--scratchpad`, or when the user's invoking message contains a natural-language opt-in phrase ("use a scratchpad", "with step tracking", "formal plan", "track steps"). Produces a scratchpad with a JSON step block (including `addresses` fields) so `/tackle-scratchpad-block` can drive execution.

Use description: `pr-{PR_NUMBER}-{COMMENT_TYPE}-{COMMENT_ID}`

Where:

- `{COMMENT_TYPE}` is: `review`, `discussion`, or `issuecomment`
- `{COMMENT_ID}` is the numeric ID from the URL (e.g., `3647271799`, `2680237139`, `987654`)

**Naming convention:** use letters (A, B, C) for feedback items in text headings. When the opt-in path applies, use `S001`, `S002` IDs for implementation steps in the JSON block. This avoids confusion when referencing "Feedback B" vs "S002".

### 5a. Default path — `/note`

Use `/note` with the description above. The note contains (all prose — no JSON step block):

````markdown
# PR https://github.com/{owner}/{repo}/pull/{PR_NUMBER} Comment Response

Source: {FULL_PR_COMMENT_URL}

## Reviewer Feedback Summary

{1-3 sentence summary of what the reviewer is asking for}

## Recommendations

{Your recommendations for the best approach, with reasoning}

## Analysis

### Feedback A: {short title}

{Analysis of first feedback item}

Decision: ACCEPT | IGNORE
Reason: {brief justification}

### Feedback B: {short title}

{Analysis of second feedback item}

Decision: ACCEPT | IGNORE
Reason: {brief justification}

Note: ACCEPT items flow to the Action Plan. IGNORE items flow to the commit message's "Ignored Feedback" section.

## Action Plan

Numbered prose steps (no fenced JSON). Each step names the feedback items it addresses (e.g. "Step 1 (addresses A, C): ...") and the specific files/functions to change. Feedback items marked IGNORE do not appear here.
````

### 5b. Opt-in path — `/scratchpad`

Use `/scratchpad` with the description above. Same sections as 5a, except `## Action Plan` is replaced with `## Implementation Plan` containing a fenced JSON step block per the `/scratchpad` Step Tracking schema. For PR-comment work:

- Omit `finish_issue_on_complete` (it is `false` by default for ad-hoc scratchpads).
- Add an `addresses` field to each step listing the feedback item letters it resolves (e.g. `"addresses": ["A", "C"]`).

Formatting: see `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.

**STOP HERE** - The template ends above. Do NOT add commit message sections to the working document. Commit messages are created separately in Step 8 (after user approval) using `/commit-msg`.

## Step 6: Questions (If Needed)

If there are decisions that need user input (not clarification from reviewer), use `/question` to create a questions file.

Only create a questions file for decisions that would fundamentally change the implementation approach.

## Step 7: Report and Stop

Print:

1. The working-document file path (labelled "note" or "scratchpad" to match which path was taken)
2. The questions file path (if created)
3. Brief summary of what you found

**IMPORTANT: Do NOT start implementing changes.**

Wait for the user to review the working document and explicitly ask you to proceed with implementation.

## Step 8: Commit Message (After User Approves)

When the user approves the plan and asks to proceed:

1. **Ask**: "Would you like me to create a commit message file now? (The implementation plan has enough context to draft it.)"

2. **If yes**: Use `/commit-msg` to create the commit message file with these specific requirements:
   - Use `[PR feedback]` as the commit type (instead of the usual type like `[refactor]` or `[fix]`)
   - Include a `Ref: {PR_COMMENT_URL}` footer to link back to the review comment
   - Do NOT include the `Co-Authored-By:` block

3. **If any reviewer feedback was ignored**: Add an `Ignored Feedback:` section after the Benefits section. For each ignored item:
   - Briefly describe the suggestion that was not implemented
   - Include reasoning for why it was skipped (prefilled based on your recommendation if the user didn't provide explicit reasoning)
   - This ensures reviewers know the feedback wasn't missed—it was intentionally declined

4. **Then**: Proceed with implementation.

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

Before finishing initial analysis (Step 7):

- [ ] Comment was fetched successfully with full thread context (if applicable)
- [ ] Working document (note or scratchpad) contains link to source PR comment
- [ ] Working document created via `/note` (default) or `/scratchpad` (opt-in) — not both
- [ ] Active-plan pointer was NOT overwritten (PR-comment scratchpads are auxiliary)
- [ ] Plan has specific file/function names
- [ ] Each step is actionable and concrete
- [ ] Recommendations explain the reasoning
- [ ] User was informed if clarification from reviewer is needed

After user approves (Step 8):

- [ ] Asked user if they want a commit message file created
- [ ] If yes, created commit message with `[PR feedback]` type and `Ref:` footer
- [ ] If any feedback was ignored, added `Ignored Feedback:` section with reasoning
