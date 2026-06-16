---
name: commit-msg
version: 2026.06.16.1@aebac85
description: Create a commit message file in .claude-work/commit-msgs/ with auto-numbered filenames. Focuses on WHY not WHAT. The diff already shows what changed. User reviews and commits manually.
argument-hint: <description>
allowed-tools: Read, Write, AskUserQuestion, Bash(git diff *), Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Commit Message

Create a commit message file in `.claude-work/`. You write the message, the user reviews and runs `git commit` themselves.

**Input:** $ARGUMENTS (a short description for the filename)

## Output format rule (read before writing anything)

See `/pre-write` for the think-before-writing rule: complete all reasoning before writing the first word.

**Every paragraph in the body is ONE continuous line.** No line breaks at 72, 80, or any fixed column. Use line breaks only for structural separation: between paragraphs, before/after the Benefits list, around code blocks. This overrides your default instinct to wrap long prose. See `/prose-style` for the full rationale.

## Core Principle

Focus on **WHY**, not **WHAT**. The git diff already shows what changed. The commit message explains the motivation, the problem being solved, and the benefits. Message depth should scale with the cognitive load of the change. Not every commit needs a body or Benefits section.

The diff is also the filter for WHICH changes to describe. If a change was added then reverted in the same working tree, it never happened. Don't mention it. Only include reasoning and decisions that relate to files and changes visible in the actual diff.

## Step 1: Resolve the Target Path

Run these two commands as parallel tool calls. They are independent.

```bash
~/.claude/skills/issue-context/target-path.sh --type commit-msgs --description "$ARGUMENTS"
```

```bash
~/.claude/skills/ensure-gitignore/ensure-gitignore.sh
```

Use the stdout of the first command as the full file path. The script handles branch detection, issue-ID extraction, directory creation, auto-numbering, and slug normalization in one call. On an `issues/<ID>` branch the output is `.claude-work/issues/<ID>/commit-msgs/NNNN-<slug>.txt`; otherwise `.claude-work/commit-msgs/NNNN-<slug>.txt`.

## Complexity Assessment

Before writing, assess the change and pick a tier. The heuristic: if you can't articulate a "why" that isn't just restating the subject, it's trivial. If the "why" fits in two sentences without needing to list outcomes, it's moderate.

**Trivial**: subject line only. Use for: CHANGELOG / docs-only updates, renaming / moving files, bumping versions or dependencies, deleting dead code, fixing typos.

**Moderate**: subject + 1-2 sentence body. Use for: bug fixes, small refactors, config changes with non-obvious motivation. The body explains why.

**Substantial**: subject + body + Benefits list. Use for: new features or capabilities, architectural changes, multi-file behavioral changes, performance improvements, security fixes.

## Capture the Actual Change Set

Run these four commands as parallel tool calls. They are independent.

```bash
git diff --stat
```

```bash
git diff
```

```bash
git diff --cached --stat
```

```bash
git diff --cached
```

### Resolve the Effective Diff

After capture, determine which diff(s) produced output:

- **Only unstaged changes (plain `git diff` produced output, `--cached` is empty):** The user hasn't staged anything. Use the plain diff as the single source of truth.
- **Only staged changes (`--cached` produced output, plain is empty):** The user staged everything. Use the cached diff.
- **Both produced output (mix):** Use `AskUserQuestion` with a single question:

  - **Header:** `Diff scope`
  - **Question:** `Both staged and unstaged changes exist. Which set should the commit message describe?`
  - **Options:**
    1. `Staged only` — commit message describes only the staged changes (ready to commit)
    2. `Both staged and unstaged` — commit message describes the full working-tree state

  Set the effective diff(s) to the chosen scope before proceeding.

Use the effective diff output as the single source of truth for what changed. Cross-reference your conversation context against it: drop any reasoning, decisions, or benefits that relate to files or edits not present in the effective diff.

## File Format

Files use `.txt` extension (not `.md`).

### First Line (all tiers)

`[type] <summary>`: imperative mood, no period, under 72 characters.

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `style`

### Trivial

```text
[docs] Add changelog entry for auto-assign feature
```

### Moderate

```text
[fix] Prevent duplicate webhook delivery on retry

The retry logic was not checking idempotency keys, causing downstream services to process the same event twice when the initial response timed out.
```

### Substantial

```text
[refactor] Separate dist/ and out/ to follow VSCode conventions

Prevents "Cannot find module" errors by separating development and production builds.
Following official conventions eliminates conflicts where tsc could overwrite esbuild's bundle.

Benefits:
- Impossible for tsc --watch to interfere with packaging
- Standard convention matching VSCode templates
```

### Rules

1. **No file lists**. Redundant with the diff.
2. **Length**: 1 line (trivial), 3-5 lines (moderate), under 15 lines (substantial).
3. **Keep the working issue link in the PR description only.** `/finish-issue` adds the `Closes` link there. That is the single source of truth for issue linkage. Repeating it in commit messages is redundant noise.
4. **Other issue/PR references are fine** when they add context (e.g., "fixes regression from `https://github.com/.../pull/42`"), include them.

### Output Anchors

Subject: [type] summary, imperative mood, no period, under 72 characters.
Length: 1 line (trivial), 3-5 lines (moderate), under 15 lines (substantial).
Format: plain text, no markdown. One continuous line per paragraph.
Tone: professional, specific, why-focused.

Formatting: see `/prose-style` for hard-wrap and GitHub-reference rules.

## Process

1. Capture the actual change set (see "Capture the Actual Change Set" above)
2. Assess the change complexity (trivial, moderate, or substantial)
3. Create the file using the matching tier format
4. **Self-check for diff-relevance.** Cross-reference the message against the diff output. Remove any mention of files, changes, or reasoning not reflected in the diff.
5. **Self-check for hard-wrapping.** Re-read the file you just wrote. For each paragraph in the body (text between blank lines, outside code blocks and the Benefits bullet list), verify it is a single continuous line. If you find a mid-sentence line break, rewrite that paragraph as one line. This check catches the most common failure. Always complete it. Also skim for AI-writing tells: em dashes, filler phrases (in order to, due to the fact that), vague attributions, generic positive conclusions. Rewrite any you find.
6. Print the filepath in terminal
7. Do NOT run `git commit`. The user reviews and commits manually.
