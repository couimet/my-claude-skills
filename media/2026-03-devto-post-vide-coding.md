---
title: "From Vide Coding to Supercharged Vibe Guiding"
published: false
description: "Vibe coding without structure is vide coding — empty results. Custom Claude Code skills turn it into something better."
tags: ai, claudecode, productivity, devtools
cover_image:
---

## It's Not a Typo

"Vide" means *empty* in French. And that's exactly what unstructured AI coding produces when the vibes run out.

I run multiple [Claude Code](https://code.claude.com/docs) agents in parallel across git worktrees every day. I'm not here to tell you to stop using AI for development. But when a SaaStr founder [lost his production database](https://fortune.com/2025/07/23/ai-coding-tool-replit-wiped-database-called-it-a-catastrophic-failure/) to an AI coding agent in July 2025, it confirmed something I'd already learned: vibes alone aren't enough.

The answer isn't less AI. It's more guidance.

## The Missing Piece: Guidance

Claude Code is powerful, but out-of-the-box sessions are ephemeral — context evaporates between tasks, there's no trail of decisions, and commits happen whenever the AI feels like it.

So I built a set of [custom skills](https://github.com/couimet/my-claude-skills) — portable markdown instructions that Claude follows when you type `/skill-name` in Claude Code ([skills are a standard Claude Code extension mechanism](https://code.claude.com/docs/en/skills)). They live in `~/.claude/skills/` — install once, use everywhere. They encode a simple contract:

- **Questions go to files, not chat.** `/question` creates a structured document I edit directly — not a conversation that scrolls away.
- **Never implement before the plan is approved.** `/scratchpad` saves plans to files I control. I iterate until I'm satisfied, and every block the AI tackles comes from a plan I've reviewed.
- **Never auto-commit.** `/commit-msg` writes a draft file. I review and commit manually.

These aren't complicated rules. But they're the difference between vide coding and what I call *vibe guiding* — you steer the AI through a structured workflow instead of hoping it gets the next thing right.

*Optional but useful: I also use [RangeLink](#about-rangelink) to navigate scratchpads with precise line references — it makes reviewing plans faster, but the skills work perfectly without it.*

## What This Looks Like in Practice

![Skill workflow diagram as of March 2026](https://raw.githubusercontent.com/couimet/my-claude-skills/main/media/2026-03-devto-post-vide-coding-workflow-diagram.svg)

*Skills keep evolving — see the [latest workflow](https://github.com/couimet/my-claude-skills#see-it-in-action) on GitHub.*

I documented a [full issue lifecycle](https://ouimet.info/follow-alongs/my-claude-skills-issues-10.html) — every artifact real, nothing fabricated. Here's the compressed version:

**1. `/start-issue`** — I point Claude at a GitHub issue. It fetches the details, creates a branch, explores the codebase, and writes an implementation plan via `/scratchpad` with concrete steps — each with its own status and defined interdependencies. Then it stops and waits.

**2. I review the plan.** Sometimes I adjust scope. Sometimes I use `/question` to surface design decisions in a structured file. The plan lives in a file I can read, edit, and come back to — not buried in a chat transcript.

**3. `/tackle-scratchpad-block`** — I point Claude at one step or a set of steps from the plan. It executes them, runs tests, updates each step's status in the scratchpad, and writes a commit message draft. It does not commit. I review the diff, review the message, and commit when I'm satisfied.

**4. Repeat** until all steps are done. Because steps have explicit interdependencies, independent ones can be tackled by parallel agents within the same worktree for faster throughput. One caveat: parallel agents may touch the same files across different tasks, so hand-picking staged blocks for truly atomic commits gets tricky — the practical trade-off is to embrace the parallelism and accept slightly larger commits.

The scratchpad evolves as I iterate — I might spin off a new `/scratchpad` with pros and cons to evaluate an approach, then integrate the decision back into the main plan. The thought process lives in files, not in my head.

**5. `/finish-issue`** — Claude runs verification (lint, tests), checks if documentation needs updating, and generates a PR description. It does not create the PR. I review and submit.

At every stage, I'm in the loop. The AI does the heavy lifting. I do the steering.

## Why This Works

Skills are workflow steps with hard stops built in. Every skill produces a file I review before anything becomes permanent — plans, questions, commit messages, PR descriptions. Nothing reaches the repo without passing through my eyes first. That's what makes it vibe *guiding*: the AI brings the force, the workflow lets me guide it.

## Try It

The skills are open source and designed to be portable — they work in any project via symlinks:

```bash
git clone git@github.com:couimet/my-claude-skills.git ~/src/my-claude-skills
~/src/my-claude-skills/install.sh
```

For the full "show the work" follow-along: [ouimet.info/follow-alongs/my-claude-skills-issues-10](https://ouimet.info/follow-alongs/my-claude-skills-issues-10.html)

## Vide → Vibe Guiding

Vibe coding is fun until the vibes run out. When they do, you're left with duplicated code instead of refactored, missing dependency injection, and untestable first drafts.

But here's what I've found: once you give the AI proper guidance through structured skills, it *continues* with that quality. Guide it toward dependency injection once, and it keeps using the pattern. Set up testable architecture in the first step, and every subsequent step follows suit.

That's supercharged vibe guiding. You're not fighting the AI or replacing it. You're giving it rails to run on — and then it runs far.

---

## About RangeLink

[RangeLink](https://github.com/couimet/rangeLink#rangelink) is an extension I built to create precise code references for AI assistants. One keybinding. Any AI, any tool. Character-level precision. Available for [VS Code](https://marketplace.visualstudio.com/items?itemName=couimet.rangelink-vscode-extension) and [Cursor](https://open-vsx.org/extension/couimet/rangelink-vscode-extension).
