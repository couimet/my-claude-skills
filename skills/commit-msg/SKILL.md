---
name: commit-msg
version: 2026.03.29@1a82381
description: Create a commit message file in .claude-work/commit-msgs/ with auto-numbered filenames. Focuses on WHY not WHAT — the diff already shows what changed. User reviews and commits manually.
argument-hint: <description>
allowed-tools: Read, Write, Bash(git branch --show-current), Bash(*/skills/auto-number/auto-number.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Commit Message

Create a commit message file in `.claude-work/`. The user reviews and runs `git commit` themselves.

**Input:** $ARGUMENTS (a short description for the filename)

## Core Principle

Focus on **WHY**, not **WHAT**. The git diff already shows what changed — the commit message explains the motivation, the problem being solved, and the benefits. Message depth should scale with the cognitive load of the change — not every commit needs a body or Benefits section.

## Step 1: Determine Target Directory and Filename

Run both commands as parallel tool calls — they are independent:

```bash
git branch --show-current
```

```bash
skills/ensure-gitignore/ensure-gitignore.sh
```

### Target directory

If the branch starts with `issues/`, extract the issue ID (characters after `issues/` up to the first `-` or `_`, only if those characters are purely numeric; otherwise use the full string after `issues/`):

- **On an issue branch:** `.claude-work/issues/<ID>/commit-msgs/`
- **Otherwise:** `.claude-work/commit-msgs/`

### Sequence number

Run:

```bash
skills/auto-number/auto-number.sh <target-directory> --glob "*.txt" --width 4 --mkdir
```

Use the stdout (e.g., `0001`) as the `NNNN` value. The `--mkdir` flag creates the directory if it does not exist, so the script works on a fresh checkout.

### Filename

`<target-directory>/NNNN-<slug>.txt` where `<slug>` is derived from $ARGUMENTS (lowercase, replace spaces and special characters with hyphens, collapse consecutive hyphens, trim leading/trailing hyphens).

Examples:

- `.claude-work/issues/332/commit-msgs/0001-add-parser.txt`
- `.claude-work/commit-msgs/0012-refactor-api.txt`

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

Never hard-wrap prose output — each paragraph is one continuous line; line breaks for structure only.

GitHub refs: full URLs only — `https://github.com/{owner}/{repo}/issues/{N}` or `https://github.com/{owner}/{repo}/pull/{N}`, never `#NNN`.

## Process

1. Assess the change complexity (trivial, moderate, or substantial)
2. Create the file using the matching tier format
3. Print the filepath in terminal
4. Do NOT run `git commit` — the user reviews and commits manually
