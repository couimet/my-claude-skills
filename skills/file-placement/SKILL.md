---
name: file-placement
user-invocable: false
description: Determines where to place files based on their purpose. Auto-consulted when Claude needs to create a new file and is deciding between .scratchpads/, .claude-questions/, .commit-msgs/, .breadcrumbs/, or docs/.
---

# File Placement

When creating a new file, use this decision tree to determine the correct location.

## Decision Tree

| Question | Destination | Skill |
| --- | --- | --- |
| Is it a question needing user input? | `.claude-questions/` | `/question` |
| Is it a commit message draft? | `.commit-msgs/` | `/commit-msg` |
| Is it a temporary working document? | `.scratchpads/` | `/scratchpad` |
| Is it a note during issue work? | `.breadcrumbs/` | `/breadcrumb` |
| Is it permanent documentation? | `docs/` or package README | N/A |

## How to Use

Evaluate from top to bottom. The first matching row determines the destination.

Each skill owns its own file format, naming conventions, and auto-numbering. Consult the referenced skill for specifics. Directory organization (flat vs issue-scoped subdirectories) is determined by the `/issue-context` skill.

## What Does NOT Go in These Directories

- Source code → appropriate `src/` directory
- Test files → co-located `__tests__/` directory
- Configuration → project root or config directory
- Dependencies → managed by package manager
