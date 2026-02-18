---
name: commit-msg
description: Create a commit message file in .commit-msgs/ with auto-numbered filenames. Focuses on WHY not WHAT — the diff already shows what changed. User reviews and commits manually.
argument-hint: <description>
allowed-tools: Read, Write, Glob, Bash(git branch --show-current)
---

# Commit Message

Create a commit message file in `.commit-msgs/`. The user reviews and runs `git commit` themselves.

**Input:** $ARGUMENTS (a short description for the filename)

## Core Principle

Focus on **WHY**, not **WHAT**. The git diff already shows what changed — the commit message explains the motivation, the problem being solved, and the benefits.

## Auto-Numbering

1. Find the highest existing number:
   ```
   Glob(pattern="*.txt", path=".commit-msgs/")
   ```
2. Increment by 1, zero-padded to 4 digits (e.g., `0001`, `0042`)
3. If no files exist, start at `0001`

## Naming Pattern

Follow the `/issue-context` skill conventions for directory organization when on an issue branch.

Base pattern: `NNNN-description.txt`

Derive the description slug from $ARGUMENTS (lowercase, hyphens, no special chars).

## File Format

Files use `.txt` extension (not `.md`).

```
[type] Short summary

<Body: Why this change? What problem does it solve? 1-3 sentences.>

Benefits:
- Key benefit 1
- Key benefit 2
```

### Format Rules

1. **First line**: `[type] <summary>`
   - Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `style`
   - Summary: imperative mood, no period, under 72 characters
2. **Body**: 1-3 sentences explaining why, not what
3. **Benefits**: Bulleted list of key outcomes
4. **Length**: Keep under 15 lines total
5. **No file lists**: Redundant with the diff
6. **No ephemeral file paths**: Never reference `.scratchpads/`, `.claude-questions/`, `.commit-msgs/`, or `.breadcrumbs/` paths — these are local working files that don't exist on GitHub

Format all prose output per the `/prose-style` skill conventions.

### Good Example

```
[refactor] Separate dist/ and out/ to follow VSCode conventions

Prevents "Cannot find module" errors by separating development and production builds.
Following official conventions eliminates conflicts where tsc could overwrite esbuild's bundle.

Benefits:
- Impossible for tsc --watch to interfere with packaging
- Standard convention matching VSCode templates
```

## Process

1. Create the file with the commit message formatted as above
2. Print the filepath in terminal
3. Do NOT run `git commit` — the user reviews and commits manually
