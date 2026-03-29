---
name: file-placement
version: 2026.03.25@43a6a52
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
| Is it a temporary working document? | `.claude-work/scratchpads/` | `/scratchpad` |
| Is it a quick note, finding, or result? | `.claude-work/notes/` | `/note` |
| Is it a note during issue work? | `.claude-work/issues/<ID>/breadcrumb.md` | `/breadcrumb` |
| Is it permanent documentation? | `docs/` or package README | N/A |

## How to Use

Evaluate from top to bottom. The first matching row determines the destination.

Each skill owns its own file format, naming conventions, and auto-numbering. Consult the referenced skill for specifics. Directory organization (flat vs issue-scoped subdirectories) is determined by the `/issue-context` skill. All ephemeral working files live under `.claude-work/`.

## Ephemeral Path Rule

`.claude-work/` paths must never appear in commits, PRs, GitHub issues, or any output visible on GitHub. These files are local-only working documents that don't exist in the repository — referencing them creates broken, meaningless links.

## What Does NOT Go in These Directories

- Source code → appropriate `src/` directory
- Test files → co-located `__tests__/` directory
- Configuration → project root or config directory
- Dependencies → managed by package manager
