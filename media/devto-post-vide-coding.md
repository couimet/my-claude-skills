---
title: "From Vide Coding to Supercharged Vibe Guiding"
published: false
description: "Vibe coding without structure is vide coding — empty results. Custom Claude Code skills turn it into something better."
tags: ai, claudecode, productivity, devtools
cover_image:
---

## It's Not a Typo

"Vide" means *empty* in French. And that's exactly what unstructured AI coding produces when the vibes run out.

I run multiple Claude Code agents in parallel across git worktrees every day. I'm not here to tell you to stop using AI for development. But when a SaaStr founder [lost his production database](https://fortune.com/2025/07/23/ai-coding-tool-replit-wiped-database-called-it-a-catastrophic-failure/) to an AI coding agent last July, it confirmed something I'd already learned: vibes alone aren't enough.

The answer isn't less AI. It's more guidance.

## The Missing Piece: A Workflow

I use [Claude Code](https://code.claude.com/docs) daily. It's powerful, but out-of-the-box sessions are ephemeral — context evaporates between tasks, there's no trail of decisions, and commits happen whenever the AI feels like it.

So I built a set of [custom skills](https://github.com/couimet/my-claude-skills) — portable markdown instructions that Claude follows when invoked ([skills are a standard Claude Code extension mechanism](https://code.claude.com/docs/en/skills)). They live in `~/.claude/skills/` — install once, use everywhere. They encode a simple contract:

- **Questions go to files, not the terminal.** `/question` creates a structured document I edit directly — not a chat that scrolls away.
- **Never implement before the plan is approved.** `/scratchpad` saves plans to files I control. I iterate until I'm satisfied, and every block the AI tackles comes from a plan I've reviewed. The skills work on their own, but I complement them with [RangeLink](https://github.com/couimet/rangeLink#rangelink) (full disclosure: I built it) for precise line-level navigation into scratchpads and commit messages.
- **Never auto-commit.** `/commit-msg` writes a draft file. I review and commit manually.

These aren't complicated rules. But they're the difference between vide coding and what I call *vibe guiding* — you steer the AI through a structured workflow instead of hoping it gets the next thing right.

## What This Looks Like in Practice

I documented a [full issue lifecycle](https://ouimet.info/follow-alongs/my-claude-skills-issues-10.html) — every artifact real, nothing fabricated. Here's the compressed version:

**1. `/start-issue`** — I point Claude at a GitHub issue. It fetches the details, creates a branch, explores the codebase, and writes an implementation plan with concrete steps. Then it stops and waits.

**2. I review the plan.** Sometimes I adjust scope. Sometimes I ask questions. The plan lives in a file I can read, edit, and come back to — not buried in a chat transcript.

**3. `/tackle-scratchpad-block`** — I point at a step. Claude executes it, runs tests, and writes a commit message draft. It does not commit. I review the diff, review the message, and commit when I'm satisfied.

**4. Repeat** until all steps are done. The scratchpad is a living document — I might spin off a `/scratchpad` with pros and cons to evaluate an approach, then integrate the decision back into the main plan. The thought process evolves in files, not in my head.

**5. `/finish-issue`** — Claude runs verification (lint, tests), checks if documentation needs updating, and generates a PR description. It does not create the PR. I review and submit.

At every stage, I'm in the loop. The AI does the heavy lifting. I do the steering.

## Why This Works

The Replit incident wasn't a freak accident — it was the logical endpoint of unsupervised AI coding. The agent *had* been told not to make changes without permission. It ignored the instruction because there was no structural enforcement.

Skills are structural enforcement. They're not suggestions in a system prompt that the AI might forget. They're workflow steps with hard stops built in. Claude literally cannot auto-commit because the commit-message skill writes to a file and exits. There's no `git commit` in the flow.

This is the difference between telling someone "please be careful" and designing a process where being careless isn't an option.

## Try It

The skills are open source and designed to be portable — they work in any project via symlinks:

```bash
git clone git@github.com:couimet/my-claude-skills.git ~/src/my-claude-skills
~/src/my-claude-skills/install.sh
```

For the full "show the work" follow-along with every artifact from a real issue lifecycle: [couimet.github.io/my-claude-skills](https://couimet.github.io/my-claude-skills/issues-10/index.html)

If you use [VS Code](https://code.visualstudio.com/), the [RangeLink](https://marketplace.visualstudio.com/items?itemName=couimet.rangelink) extension turns code references in scratchpads and commit messages into clickable navigation links — useful when reviewing plans before approving them.

## Vide → Vibe Guiding

Vibe coding is fun until the vibes run out. When they do, you're left with duplicated code instead of refactored, missing dependency injection, untestable first drafts, and — in extreme cases — deleted production databases.

But here's what I've found: once you give the AI proper guidance through structured skills, it *continues* with that quality. Guide it toward dependency injection once, and it keeps using the pattern. Set up testable architecture in the first step, and every subsequent step follows suit.

That's supercharged vibe guiding. You're not fighting the AI or replacing it. You're giving it rails to run on — and then it runs far.
