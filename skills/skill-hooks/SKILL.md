---
name: skill-hooks
version: 2026.06.16.1@aebac85
description: Explains the skill extension hook mechanism — how projects can customize global skills like /start-issue and /finish-issue with project-local additions
user-invocable: false
allowed-tools:
---

# Skill Hooks

Explains the hook mechanism that lets projects extend global skills with project-local requirements. Consulted automatically by skills that support hooks. Not invoked directly by the user.

## How It Works

Some skills in this collection (like `/start-issue`, `/finish-issue`, and `/start-side-quest`) include hook points — prose references to a companion skill that a project can optionally define. When the parent skill runs, Claude Code resolves the hook reference across all skill directories. If the project has the hook skill, its requirements are incorporated. If not, the vanilla skill runs unchanged.

## Convention

A project creates a foundation skill in `.claude/skills/` with the name `{parent-skill}-hooks`:

| Parent skill | Hook skill name | What it can add |
| --- | --- | --- |
| `/start-issue` | `start-issue-hook` | Additional plan steps, context-gathering, validation gates |
| `/finish-issue` | `finish-issue-hook` | Additional verification steps, PR description sections |
| `/start-side-quest` | `start-side-quest-hook` | Additional plan steps, context-gathering, validation gates |

Hook skills are foundation skills (`user-invocable: false`). They are consulted by their parent skill, never invoked directly by the user.

## Scope

Hooks add requirements — they cannot replace the parent skill's behavior. The parent skill owns all decisions; the hook contributes constraints and content. This optimizes for frugal token consumption: the parent skill doesn't branch on hook existence, and projects without hooks pay zero overhead.

Projects wanting to replace specific behaviors (e.g., changing where `/note` writes files) should use CLAUDE.md instructions or fork the repo and add yield points at the decisions they need to customize.

## Example

RangeLink wants every issue plan to cross-reference QA test cases. It creates `.claude/skills/start-issue-hook/SKILL.md`:

```yaml
---
name: start-issue-hook
description: QA test case cross-referencing for /start-issue plans
user-invocable: false
allowed-tools: Read, Grep, Glob
---

# Start-Issue Hooks (RangeLink)

Consulted automatically by /start-issue.

## Additional Plan Requirements

Every plan must include a step that identifies affected QA test cases. Read the current QA YAML and cross-reference with the changed areas.

## Additional Context Gathering

Before writing the plan, read `qa/qa-test-cases.yaml` to understand current TC coverage.
```

A project without this file gets the vanilla `/start-issue` behavior with no changes.

## Design Rationale

The full architecture decision record is at [`docs/ADR/001-skill-extension-hooks.md`](../../docs/ADR/001-skill-extension-hooks.md). It covers the problem, the resolution mechanism, why add-requirements-only was chosen, and why alternatives (same-name overrides, CLAUDE.md instructions, behavior-replacement hooks) were rejected.
