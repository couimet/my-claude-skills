---
name: commit-msg
version: 2026.04.24@2423d79
description: Create a commit message file in .claude-work/commit-msgs/ with auto-numbered filenames. Focuses on WHY not WHAT — the diff already shows what changed. User reviews and commits manually.
argument-hint: <description>
allowed-tools: Read, Write, Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Commit Message

Create a commit message file in `.claude-work/`. The user reviews and runs `git commit` themselves.

**Input:** $ARGUMENTS (a short description for the filename)

## Output format rule (read before writing anything)

**Every paragraph in the body is ONE continuous line.** No line breaks at 72, 80, or any fixed column. Use line breaks only for structural separation: between paragraphs, before/after the Benefits list, around code blocks. This overrides your default instinct to wrap long prose. See `/prose-style` for the full rationale.

## Core Principle

Focus on **WHY**, not **WHAT**. The git diff already shows what changed — the commit message explains the motivation, the problem being solved, and the benefits. Message depth should scale with the cognitive load of the change — not every commit needs a body or Benefits section.

## Step 1: Resolve the Target Path

Run these two commands as parallel tool calls — they are independent.

```bash
~/.claude/skills/issue-context/target-path.sh --type commit-msgs --description "$ARGUMENTS"
```

```bash
~/.claude/skills/ensure-gitignore/ensure-gitignore.sh
```

Use the stdout of the first command as the full file path. The script handles branch detection, issue-ID extraction, directory creation, auto-numbering, and slug normalization in one call. On an `issues/<ID>` branch the output is `.claude-work/issues/<ID>/commit-msgs/NNNN-<slug>.txt`; otherwise `.claude-work/commit-msgs/NNNN-<slug>.txt`.

## Complexity Assessment

Before writing, assess the change and pick a tier. The heuristic: if you can't articulate a "why" that isn't just restating the subject, it's trivial. If the "why" fits in two sentences without needing to list outcomes, it's moderate.

**Trivial** — subject line only. Use for: CHANGELOG / docs-only updates, renaming / moving files, bumping versions or dependencies, deleting dead code, fixing typos.

**Moderate** — subject + 1-2 sentence body. Use for: bug fixes, small refactors, config changes with non-obvious motivation. The body explains why.

**Substantial** — subject + body + Benefits list. Use for: new features or capabilities, architectural changes, multi-file behavioral changes, performance improvements, security fixes.

## File Format

Files use `.txt` extension (not `.md`).

### First Line (all tiers)

`[type] <summary>` — imperative mood, no period, under 72 characters.

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

1. **No file lists** — redundant with the diff
2. **Length** — trivial: 1 line; moderate: 3-5 lines; substantial: under 15 lines
3. **Never include the current working issue link** — `/finish-issue` adds the `Closes` link to the PR description. That's the single source of truth for issue linkage. Repeating it in commit messages is redundant noise.
4. **Other issue/PR references are fine** — when they add context (e.g., "fixes regression from `https://github.com/.../pull/42`"), include them.

Formatting: see `/prose-style` for hard-wrap and GitHub-reference rules.

## Process

1. Assess the change complexity (trivial, moderate, or substantial)
2. Create the file using the matching tier format
3. **Self-check for hard-wrapping.** Re-read the file you just wrote. For each paragraph in the body (text between blank lines, outside code blocks and the Benefits bullet list), verify it is a single continuous line. If you find a mid-sentence line break, rewrite that paragraph as one line. This check catches the most common failure — do not skip it.
4. Print the filepath in terminal
5. Do NOT run `git commit` — the user reviews and commits manually
