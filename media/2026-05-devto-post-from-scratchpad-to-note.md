---
title: "I sold you on /scratchpad. Then I migrated to /note."
published: https://dev.to/couimet/i-sold-you-on-scratchpad-then-i-migrated-to-note-4n1o
description: "Two months ago I sold a scratchpad-driven workflow. The default just moved to a lighter note format. Here's what changed and why."
tags: ai, claude, productivity, devtools
cover_image:
---

This is the third post in a series that started with [vibe guiding](https://dev.to/couimet/from-vide-coding-to-supercharged-vibe-guiding-6nm) and continued with an [efficiency audit](https://dev.to/couimet/i-thought-i-was-dry-ing-i-may-have-been-double-paying-5dli). Two months ago I laid out the four-skill loop: `/start-issue` writes a `/scratchpad`, `/tackle-scratchpad-block` executes one step at a time, status flags transition from `pending` to `done`, and `/finish-issue` reads what shipped and writes the PR title + description.

## Why I changed my mind

The driver was token consumption. My employer gave each team dashboards of our AI tool usage and I was always the top consumer on mine — fairly high on the department chart too. That's when I started to suspect it was not what I was building but how I was working with the tools.

`/scratchpad`'s JSON step block and `/tackle-scratchpad-block` chain meant every task paid the same ceremony tax: status flags to transition, JSON to validate, a fenced block to parse. Useful scaffolding for multi-hour work. Overhead I was paying on every session. If my process was the reason I topped the dashboard, revisiting it was the cheapest experiment I could run.

Once I started looking, the redundancy wasn't only scratchpad-vs-note. The templates the composite skills were generating — what `/start-issue`, `/start-side-quest`, `/tackle-pr-comment`, and `/finish-issue` wrote into their output documents — carried weight they didn't need. A few examples from the audit that led to [PR 130](https://github.com/couimet/my-claude-skills/pull/130):

- `## Files to Modify` re-grouped information the Plan steps already named, just organized by file.
- `## Documentation & Discoverability` was a pre-populated checklist that `/finish-issue` already re-derived systematically at wrap-up time.
- `## Acceptance Criteria` had Claude copy criteria verbatim from the issue body it already had in context.
- `## Why Split This Out` was three hardcoded bullets that matched every side-quest ever created.

Each of these was small on its own. Cumulatively they were a per-session surtax, paid every time a skill fired. Defaulting to `/note` instead of `/scratchpad` was the biggest single cut, but the pattern of the change was wider: stop having the LLM write the same information twice, in different shapes, into different documents.

## Claude was changing too

The other thing that shifted in those months was Claude itself. When I first wrote about this, the hard stops at every step made sense for the Claude that was around then. By the time [PR 130](https://github.com/couimet/my-claude-skills/pull/130) landed, Claude had gotten noticeably better at multi-step self-organization across an issue. I could lower my guard a bit. The *control-freak posture* I had started with was no longer needed. If I wanted an explicit checkpoint to manually review and commit, I could simply add a step in the generated `/note`.

Parallelism shifted too. Claude gained the ability to fan out workers and run agents in parallel within a single session, which meant on issues with independent pieces Claude could organize its own throughput faster than I could shepherd it through the `/tackle-scratchpad-block` chain. The gates that had once added safety started adding latency. By gating with `/tackle-scratchpad-block`, I was slowing Claude down by asking for more control.

## What `/note` looks like

A `/scratchpad`'s `## Implementation Plan` section is a fenced JSON block with status fields, dependency arrays, and task lists:

```json
{
  "finish_issue_on_complete": false,
  "steps": [
    {
      "id": "S001",
      "title": "Swap the token library",
      "status": "pending",
      "done_when": "Old lib removed from package.json, new one imported and passing existing tests",
      "depends_on": [],
      "files": ["package.json", "src/auth/token.ts"],
      "tasks": [
        "npm install new-token-lib, npm remove old-token-lib",
        "Update src/auth/token.ts imports",
        "Run the token test suite"
      ]
    },
    {
      "id": "S002",
      "title": "Update callers to match new token API",
      "status": "pending",
      "depends_on": ["S001"],
      "files": ["src/middleware/auth.ts", "src/routes/login.ts"],
      "tasks": [
        "Update verifyToken() call sites to new API shape",
        "Run full test suite"
      ]
    }
  ]
}
```

A `/note`'s `## Plan` section is the same information without the scaffolding:

```text
1. Swap the token library — npm install new-token-lib, update imports, run the token test suite
2. Update callers to match the new token API — verifyToken() call sites, full test suite
```

No fenced JSON block. No `status: pending`. The plan says what to do and in what order; the LLM organizes its own execution in-session. The hard stops from the original workflow are still there: I read the plan before saying "go ahead", I review the diff, I commit when I'm satisfied. The commit lands at the end of the note, not after every step. If I want an earlier checkpoint, I add an explicit gate in the plan.

![Note-vs-scratchpad workflow](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/oac83codonnv3gqkcrfj.png)

`/scratchpad` is still there. You opt in two ways: pass `--scratchpad` to the invoking skill, or use one of the natural-language triggers the skill watches for ("use a scratchpad", "with step tracking", "formal plan", "track steps"). I still reach for it when I'm working through a larger GitHub issue and want a commit after each step instead of one at the end. This is especially helpful when I'm juggling two or three worktrees on the same project — iterative commits and step tracking keep me oriented when my attention is split across parallel branches.

## What I am taking away

The `/note` flow still stops for plan review before anything happens, then gives the LLM more autonomy to fan out and move faster. The `/scratchpad` flow is still powerful — but you don't always need a bazooka to kill a fly. Most days the lighter tool is enough, ending on a high *note*.

## If you already use these skills

Pull the latest from the repo and run `./setup.sh` to symlink the updated set. `/start-issue` will produce a `/note` on your next invocation. Nothing else changes — the rest of the loop carries on. If you want the old behavior, type `--scratchpad`.

*Written using the same skills it describes, starting from [issue #139](https://github.com/couimet/my-claude-skills/issues/139). The plan was a note this time.*
