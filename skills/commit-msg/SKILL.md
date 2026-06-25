---
name: commit-msg
version: 2026.06.25@7353cfe
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

Always create a new file. Never edit an existing commit-msg file. `target-path.sh` already guarantees unique filenames via auto-numbering. Old files stay on disk as historical artifacts. Two invocations without an intermediate commit simply produce two files — the user picks whichever they want at commit time.

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

  Set the effective diff(s) to the chosen scope before proceeding. The corresponding stat output — `git diff --stat` for unstaged, `git diff --cached --stat` for staged, or both combined for "Both" — becomes the source for the `Files:` footer.

**Gate** (a hard checkpoint — must be satisfied, not a suggestion): **exclude already-committed topics.** Use the effective diff output as the single source of truth for what changed. If a change, fix, or decision was discussed in the conversation but does NOT appear in the effective diff, it is not part of this change set. Exclude it from this message. The message describes ONLY the changes visible in THIS diff.

## File Format

Files use `.txt` extension (not `.md`).

### First Line (all tiers)

`[type] <summary>`: imperative mood, no period, under 72 characters.

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `style`

### Trivial

```text
[docs] Add changelog entry for auto-assign feature
Files: CHANGELOG.md (+3)
```

### Moderate

```text
[fix] Prevent duplicate webhook delivery on retry

The retry logic was not checking idempotency keys, causing downstream services to process the same event twice when the initial response timed out.
Files: src/webhooks/delivery.ts (+12)
```

### Substantial

```text
[refactor] Separate dist/ and out/ to follow VSCode conventions

Prevents "Cannot find module" errors by separating development and production builds.
Following official conventions eliminates conflicts where tsc could overwrite esbuild's bundle.

Benefits:
- Impossible for tsc --watch to interfere with packaging
- Standard convention matching VSCode templates
Files: tsconfig.json (+8, -3), package.json (+2, -2), scripts/build.sh (+5)
```

### Rules

1. **No file lists in prose.** The `Files:` footer is a structured metadata line derived from the effective diff's stat output, not a prose list. Do not enumerate files in the body.
2. **Body length**: 1 line (trivial), 1-2 lines (moderate), under 15 lines (substantial). The subject line and `Files:` footer do not count toward the body line budget.
3. **Keep the working issue link in the PR description only.** `/finish-issue` adds the `Closes` link there. That is the single source of truth for issue linkage. Repeating it in commit messages is redundant noise.
4. **Other issue/PR references are fine** when they add context (e.g., "fixes regression from `https://github.com/.../pull/42`"), include them.

### Output Anchors

Subject: [type] summary, imperative mood, no period, under 72 characters.
Body length: 1 line (trivial), 1-2 lines (moderate), under 15 lines (substantial). The subject line and `Files:` footer do not count toward the body line budget.
Format: plain text, no markdown. One continuous line per paragraph. Every message ends with a `Files:` line derived from the effective diff's stat output. Derive the `Files:` line by parsing each stat line into `path (+N, -N)`, omitting `-N` when zero, joining with commas, and skipping the summary line.
Tone: professional, specific, why-focused.

Formatting: see `/prose-style` for hard-wrap and GitHub-reference rules.

## Process

1. Capture the actual change set (see "Capture the Actual Change Set" above)
2. Assess the change complexity (trivial, moderate, or substantial)
3. Write the file using the matching tier format, including the `Files:` footer derived from the effective diff's stat output
4. **Self-check for diff-relevance (Gate).** If a change, fix, or decision was discussed in the conversation but does NOT appear in the effective diff, it is not part of this change set. Remove it from this message. The message describes ONLY the changes visible in THIS diff.
5. **Self-check for hard-wrapping.** Re-read the file you just wrote. For each paragraph in the body (text between blank lines, outside code blocks and the Benefits bullet list), verify it is a single continuous line. If you find a mid-sentence line break, rewrite that paragraph as one line. This check catches the most common failure. Always complete it. Also skim for AI-writing tells: em dashes, filler phrases (in order to, due to the fact that), vague attributions, generic positive conclusions. Rewrite any you find.
6. Print the filepath in terminal
7. Do NOT run `git commit`. The user reviews and commits manually.
