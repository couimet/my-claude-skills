---
name: prose-style
version: 2026.02.28@bc451e4
user-invocable: false
description: Documents the prose no-wrap convention used by skill-generated files. Rules are now embedded directly in each skill via an explicit inline instruction and a <!-- markdownlint-disable MD013 --> header in generated files, rather than referenced as a sub-skill.
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

## How Rules Are Applied

These rules are no longer distributed by referencing this skill. Instead, each skill that generates files embeds the convention in two places:

**1. Generated file header** — every generated file starts with `<!-- markdownlint-disable MD013 -->` as its first line. This signals to Claude (when reading or editing the file) and to markdown-aware tools that line length is not enforced in this file.

**2. Inline instruction in the skill** — each SKILL.md that generates prose content includes the explicit rule: "Never hard-wrap prose output — each paragraph is one continuous line; line breaks for structure only." This replaces the previous "Format all prose output per the `/prose-style` skill conventions." footer.

Skills that generate files with the `<!-- markdownlint-disable MD013 -->` header: `scratchpad`, `commit-msg`, `question`, `breadcrumb`, `finish-issue` (PR description templates).
