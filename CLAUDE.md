# CLAUDE.md — my-claude-skills

This file provides guidance for AI agents working inside the `my-claude-skills` repository. It covers development workflow, skills architecture, conventions, and rules.

## Project Purpose

This repository is a collection of portable Claude Code skills. Each skill is a `SKILL.md` file inside a `skills/<name>/` directory. Skills are installed globally at `~/.claude/skills/` (via symlinks) and loaded by Claude Code when a user types `/skill-name`. The repo's goal is to encode repeatable workflows — issue triage, PR feedback, scratchpad-driven implementation — as portable, composable instructions.

## Development Commands

Run all commands from the project root.

| Command | What it does |
| --- | --- |
| `make all` | Run lint + test (default target) |
| `make lint` | `markdownlint-cli2 "**/*.md"` — lint all Markdown files |
| `make lint-fix` | `markdownlint-cli2 --fix "**/*.md"` — auto-fix lint issues |
| `make test` | `bats tests/` — run the bats test suite |
| `make stamp` | Stamp `version: <CalVer>@<SHA>` into all `skills/*/SKILL.md` front matter; reads CalVer from the latest `CHANGELOG.md` heading and SHA from `git rev-parse --short HEAD` |

**After every change:** run `make lint && make test` before committing. Both must pass.

## Skills Architecture

### SKILL.md Front Matter

Every skill begins with a YAML front matter block:

```yaml
---
name: skill-name
version: 2026.03.01@abc1234        # stamped by `make stamp` — do not edit manually
description: One-sentence summary of what the skill does
argument-hint: <github-issue-url>  # optional; shown as hint in the UI
user-invocable: false              # omit or set true for user-facing skills; false = foundation skill
allowed-tools: Read, Write, Glob, Grep, Bash(git status *), Bash(gh issue view *)
---
```

**`user-invocable: false`** — marks a skill as a foundation (sub) skill. Foundation skills are consulted automatically by other skills but are not directly invoked by the user. Examples: `issue-context`, `auto-number`, `code-ref`, `github-ref`.

**`allowed-tools:`** — restricts which Bash commands the skill may use. Use specific patterns (`Bash(git checkout *)`) rather than `Bash(*)` unless the skill genuinely needs unrestricted shell access (only `tackle-scratchpad-block` does, because it runs arbitrary user-authored steps).

**`version:`** is managed by `make stamp` — never edit it by hand.

### Skill Cross-References

Skills reference each other using `/skill-name` syntax in prose (e.g., "Use `/scratchpad` to create a working document."). When Claude encounters this, it loads the referenced skill's SKILL.md as additional context.

### Invocable vs Foundation Skills

| Type | `user-invocable` | Loaded by |
| --- | --- | --- |
| User-facing | `true` (or omitted) | User types `/skill-name` |
| Foundation | `false` | Other skills reference them via `/skill-name` in prose |

## Workflow

### Issue Workflow

Work on GitHub issues follows this chain:

1. `/start-issue <url>` — fetches the issue, creates an `issues/<NUMBER>` branch, explores the codebase, and writes an implementation plan scratchpad
2. `/tackle-scratchpad-block <path>` — executes one step from the scratchpad, runs tests, creates a commit message file
3. `/finish-issue` — runs verification (lint, tests), checks documentation needs, generates a PR description scratchpad

### Rules

- **Never auto-commit.** Always write a commit message file and let the user review and commit manually.
- **Always use the workflow skills.** Don't bypass `/start-issue` to create branches directly; don't skip `/finish-issue` before opening a PR.
- **Never implement before the user approves the plan.** Skills that end with "STOP" mean it — wait for explicit user go-ahead ("proceed", "go ahead", "implement").
- **Questions go to files, not terminal.** Use `/question` to create a questions file; never print design questions inline in the response.

## Working Files

All ephemeral working files live under `.claude-work/` (git-ignored). Never commit this directory or reference its paths in commit messages, PR descriptions, or GitHub issues — these files don't exist on GitHub and the references would be meaningless.

**Directory layout:**

```text
.claude-work/
  issues/<ID>/
    scratchpads/   ← implementation plans (NNNN-description.txt)
    questions/     ← design decision files (NNNN-description.txt)
    commit-msgs/   ← commit message drafts (NNNN-description.txt)
    breadcrumb.md  ← running notes collected by /finish-issue
  scratchpads/     ← flat placement when not on an issues/* branch
  questions/
  commit-msgs/
```

**Auto-numbering:** File sequence numbers (`NNNN`) are managed by `skills/auto-number/auto-number.sh`. Foundation skills call it automatically — don't reimplement the logic.

## CHANGELOG Conventions

This project uses [Calendar Versioning](https://calver.org/): `YYYY.MM.DD`. When multiple releases land the same day, append a micro suffix: `2026.03.01.1`, `2026.03.01.2`, etc.

**Heading format:** `## YYYY.MM.DD` (or `## YYYY.MM.DD.N`). Before adding an entry, check whether a heading for today already exists — if it does, create a new heading with the next micro suffix rather than adding to the existing one.

**Category subsections** (only include ones that apply):

- `### Added` — new skills, new features, new files
- `### Changed` — modifications to existing skills or behavior
- `### Fixed` — bug fixes
- `### Removed` — deleted skills or removed features

**When to add an entry:** User-facing changes (new skill, changed behavior, bug fix, removed skill) always get entries. Pure internal changes (new tests, refactors, CI updates) with no user-facing effect do NOT get entries.

**Link to the issue:** End each entry with `([issues/NN](https://github.com/couimet/my-claude-skills/issues/NN))`.

## Prose Formatting

All prose in files generated by skills (scratchpads, questions, commit messages, PR descriptions) must follow these rules:

- **No hard wrapping** — never break lines at 72, 80, or any fixed column width
- **One line per paragraph** — each paragraph or logical block is a single continuous line
- **Structural breaks only** — use line breaks between paragraphs, before/after lists, between sections, and around code blocks
