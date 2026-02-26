---
name: prose-style
version: 2026.02.25@abc1234
user-invocable: false
description: Defines prose formatting conventions for skill-generated text files. Auto-consulted when any skill writes prose content to .claude-work/ (scratchpads, commit-msgs, questions, breadcrumbs) or PR descriptions.
---

# Prose Style

When generating text files, let prose flow naturally. Never hard-wrap at a fixed column width.

## Rules

1. **No hard wrapping** — do not break lines at 72, 80, or any other fixed column width
2. **One line per paragraph** — write each paragraph or logical block as a single continuous line
3. **Structural breaks only** — use line breaks for separation between paragraphs, before/after lists, between sections, and around code blocks

## What to Leave Alone

- **Headings** — naturally one line
- **List items** — each item is its own line
- **Code blocks** — preserve their internal formatting
- **Commit subject lines** — the first line of a commit message follows its own conventions (imperative mood, under 72 characters); this skill applies to body text only
