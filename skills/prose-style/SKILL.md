---
name: prose-style
version: 2026.08.19.1@8e9c94b
user-invocable: false
description: Canonical prose and reference formatting rules for any skill that writes to a file: hard-wrap rule, code reference syntax, GitHub reference syntax. Auto-consulted whenever a skill produces file content.
allowed-tools: Bash(gh repo view *)
---

# Prose Style

Single source of truth for how skill-generated text is written. Three rules, all of which previously lived as three-line epilogues copied into every user-invocable skill.

## Rule 1: Each paragraph is one continuous line

**Write each paragraph as ONE continuous line, no matter how long.** Use line breaks for *structure* only: between paragraphs, before/after lists, between sections, around code blocks. Do NOT insert line breaks at 72, 80, or any fixed column to make the text "look nicer." Your default instinct will be to wrap; override it.

This applies to every file a skill produces: scratchpads, questions, commit messages, PR descriptions, notes, breadcrumbs, CHANGELOG entries, article drafts.

### Format Anchors

Format: one continuous line per paragraph, no hard wrapping. Code references: path/to/file.ts#L10 (bare in file content, never backtick-wrapped). GitHub references: full URL only. Generated file paths in terminal output: absolute only.

### Self-check before you finish

Before reporting a file path back to the user, re-read the file you just wrote. For each paragraph (text between blank lines, not inside a code block or table), verify it is a single continuous line. If you find any mid-sentence line break, rewrite that paragraph as one line. This check is cheap and catches the most common failure mode.

Also skim for AI-writing tells: em dashes, filler phrases (in order to, due to the fact that), vague attributions, generic positive conclusions. Rewrite any you find.

## Rule 2: Code references (in file content)

Use GitHub-style permalink syntax so references become clickable in RangeLink and similar tools. This rule applies to code references written inside generated files (scratchpads, questions, commit messages, PR descriptions). It does NOT apply to terminal output reporting generated file paths — see Rule 4 for that.

| Reference type | Syntax | Example |
| --- | --- | --- |
| Single line | `path/to/file.ts#L10` | src/parser.ts#L42 |
| Line range | `path/to/file.ts#L10-L20` | src/parser.ts#L42-L58 |
| Char precision | `path/to/file.ts#L10C5-L20C15` | src/parser.ts#L42C3-L42C28 |

- Workspace-relative paths only (never absolute).
- Write paths bare, without backticks. Backticks become part of the parsed path and break navigation.
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

## Rule 4: Generated file paths in terminal output must be absolute

When reporting a generated file path to the user (e.g., "Created: ...", "File: ...", "Breadcrumb dropped in ..."), always use the full absolute path. Absolute paths are clickable in terminal and IDE (CMD+CLICK). Relative paths (`.claude-work/...`) are not — they break when the current working directory differs from the project root, as happens in git worktrees where `.claude-work/` is at the main checkout root.

This applies to every skill that prints a file path: notes, scratchpads, questions, commit messages, PR descriptions, breadcrumbs.

## What this replaces

Callers no longer need to repeat the rules. Auto-consultation of `/prose-style` via this skill's description covers it.
