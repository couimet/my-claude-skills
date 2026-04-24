---
name: file-placement
version: 2026.04.24@2423d79
user-invocable: false
description: Determines where to place files based on their purpose. Auto-consulted when Claude needs to create a new file and is deciding between .claude-work/ subdirectories or docs/.
---

# File Placement

When creating a new file, use this decision tree to determine the correct location.

## Decision Tree

| Question | Destination | Skill |
| --- | --- | --- |
| Is it a question needing user input? | `.claude-work/questions/` | `/question` |
| Is it a commit message draft? | `.claude-work/commit-msgs/` | `/commit-msg` |
| Is it a quick note, finding, or result? | `.claude-work/notes/` | `/note` |
| Is it a temporary working document with formal step tracking? | `.claude-work/scratchpads/` | `/scratchpad` |
| Is it a note during issue work? | `.claude-work/issues/<ID>/breadcrumb.md` | `/breadcrumb` |
| Is it permanent documentation? | `docs/` or package README | N/A |

## How to Use

**Composite skills default to `/note`.** `/start-issue`, `/start-side-quest`, `/tackle-pr-comment`, and `/finish-issue` all create a `/note` by default and only fall back to `/scratchpad` when the user explicitly opts in (`--scratchpad` flag or equivalent natural-language trigger). The opt-in path is reserved for workflows that want `/tackle-scratchpad-block` to drive execution against a JSON step block; otherwise, the LLM self-organizes in-session.

Evaluate from top to bottom. The first matching row determines the destination.

Each skill owns its own file format, naming conventions, and auto-numbering. Consult the referenced skill for specifics. For the numbered working-file skills — `/scratchpad`, `/question`, and `/commit-msg` — directory organization (flat vs issue-scoped subdirectories) is handled by `~/.claude/skills/issue-context/target-path.sh`, which those skills call internally. `/note` uses timestamp-based filenames and detects branch context on its own; `/breadcrumb` writes a single file per issue directly. All ephemeral working files live under `.claude-work/`.

## Ephemeral Path Rule

`.claude-work/` paths must never appear in commits, PRs, GitHub issues, or any output visible on GitHub. These files are local-only working documents that don't exist in the repository — referencing them creates broken, meaningless links.

## What Does NOT Go in These Directories

- Source code → appropriate `src/` directory
- Test files → co-located `__tests__/` directory
- Configuration → project root or config directory
- Dependencies → managed by package manager
