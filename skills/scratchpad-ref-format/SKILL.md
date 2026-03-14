---
name: scratchpad-ref-format
user-invocable: false
description: Defines the 4 invocation forms for referencing scratchpad steps — step-ID (#S), line-range (#L), space-separated, and bare-path auto-select. Auto-consulted by /tackle-scratchpad-block when parsing its argument.
allowed-tools: Read
---

# Scratchpad Reference Format

When invoking `/tackle-scratchpad-block`, the argument selects which step to execute. Four forms are supported:

## Forms

| Form | Syntax | Example |
| --- | --- | --- |
| Step-ID (preferred) | `path#S00N` | `.claude-work/issues/42/scratchpads/0001-plan.txt#S003` |
| Line-range | `path#L10-L20` | `.claude-work/issues/42/scratchpads/0001-plan.txt#L25-L67` |
| Space-separated | `path S00N` | `.claude-work/issues/42/scratchpads/0001-plan.txt S003` |
| Bare path (auto-select) | `path` | `.claude-work/issues/42/scratchpads/0001-plan.txt` |

## Parsing Rules

**Step-ID (`#S`):** Extract the ID after `#S` (e.g., `S003`), read the full scratchpad, and locate the step whose `"id"` field matches exactly.

**Line-range (`#L`):** Read those exact lines from the file. Power-user escape hatch for re-running or overriding a step.

**Space-separated:** Equivalent to `#S` form — useful in environments where `#` in arguments is awkward. Match the trailing token (`S\d+`) to a step `"id"`.

**Bare path (auto-select):** Read the full scratchpad, find all steps where `"status"` is `"pending"` and every entry in `"depends_on"` resolves to a step with `"status": "done"`.

- One candidate: proceed with it.
- Multiple candidates: list them and STOP — wait for the user to pick one.
- No candidates: report "All steps are done or blocked." and STOP.

## Error Handling

If the reference doesn't resolve (file not found, step ID not in JSON, lines don't exist, or content isn't actionable steps): STOP immediately and report the issue. Do not guess, search for alternatives, or infer intent.
