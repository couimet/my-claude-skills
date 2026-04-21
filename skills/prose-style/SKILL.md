---
name: prose-style
version: 2026.04.20@f632eaa
user-invocable: false
description: Canonical prose and reference formatting rules for any skill that writes to a file — hard-wrap rule, code reference syntax, GitHub reference syntax. Auto-consulted whenever a skill produces file content.
allowed-tools: Bash(gh repo view *)
---

# Prose Style

Single source of truth for how skill-generated text is written. Three rules, all of which previously lived as three-line epilogues copied into every user-invocable skill.

## Rule 1: No hard wrapping

Never break prose at 72, 80, or any fixed column. Each paragraph or logical block is one continuous line. Use line breaks for *structure* only — between paragraphs, before/after lists, between sections, around code blocks.

This applies to every file a skill produces: scratchpads, questions, commit messages, PR descriptions, notes, breadcrumbs, CHANGELOG entries, article drafts.

## Rule 2: Code references

Use GitHub-style permalink syntax so references become clickable in RangeLink and similar tools.

| Reference type | Syntax | Example |
| --- | --- | --- |
| Single line | `path/to/file.ts#L10` | src/parser.ts#L42 |
| Line range | `path/to/file.ts#L10-L20` | src/parser.ts#L42-L58 |
| Char precision | `path/to/file.ts#L10C5-L20C15` | src/parser.ts#L42C3-L42C28 |

- Workspace-relative paths only (never absolute).
- Never wrap in backticks — the backticks become part of the parsed path and break navigation.
- Never use plain-text forms like "lines 26-37", "Line 539", or "(L42-L58)".

## Rule 3: GitHub references

Never use `#NNN`, `PR #NNN`, or `issue #NNN` in any skill-generated output. Short forms are ambiguous across repositories.

| Reference type | Full URL format |
| --- | --- |
| Issue | `https://github.com/{owner}/{repo}/issues/{number}` |
| Pull request | `https://github.com/{owner}/{repo}/pull/{number}` |

Construction:

- If the full URL is already available (user passed it in, or it appears in tool output), use it directly.
- If only the number is in context, build the URL from the current remote:

```bash
gh repo view --json url -q .url
```

Then append `/issues/{number}` or `/pull/{number}`.

## What this replaces

Before 2026-04-20, the three rules above appeared as repeated epilogues in ~11 user-invocable skills, plus as separate `/code-ref` and `/github-ref` foundation skills. The audit at [issues/120](https://github.com/couimet/my-claude-skills/issues/120) consolidated everything here. Callers no longer need to repeat the rules — auto-consultation of `/prose-style` via this skill's description covers it.
