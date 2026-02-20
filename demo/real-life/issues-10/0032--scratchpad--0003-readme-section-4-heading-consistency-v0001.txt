# README Section 4 Heading Consistency

## Problem

In the "See It In Action" walkthrough, steps 2, 3, and 5 follow the pattern `### N. `/skill-name` — brief description` which renders the skill command in a visually prominent monospace box on GitHub. Step 1 breaks this pattern:

Current:
- `### 1. Pre-planning: explore before committing to a plan`
- `### 2. `/start-issue` — branch + implementation plan` (promoted)
- `### 3. `/tackle-scratchpad-block` — execute one step at a time` (promoted)
- `### 4. Side-quests and breadcrumbs`
- `### 5. `/finish-issue` — wrap up with a PR description` (promoted)

Step 1's body text mentions both `/scratchpad` and `/question`, but the heading doesn't promote either skill. A reader scanning headings gets no signal that this step involves specific skill invocations.

## Options

### Option A: Promote `/scratchpad` as the lead skill

`### 1. `/scratchpad` + `/question` — explore before committing to a plan`

PROS:
- Names both skills used in this phase, matching the explicitness of other headings
- Readers scanning headings see the full skill vocabulary at a glance
- The `+` connector naturally suggests "used together" rather than "pick one"
- Consistent backtick rendering with steps 2, 3, 5

CONS:
- Two skill names in one heading is visually heavier than the single-skill pattern
- The `+` connector is a new pattern not used elsewhere in the walkthrough
- Pre-planning is conceptually broader than a single skill invocation — the heading might oversimplify

### Option B: Promote `/scratchpad` only, mention `/question` in body

`### 1. `/scratchpad` — explore before committing to a plan`

PROS:
- Clean single-skill heading matching the exact pattern of steps 2, 3, 5
- `/scratchpad` is the primary output of this phase (the plan document)
- `/question` is already well-explained in the body text — doesn't need heading-level promotion
- Simplest change — one line edit

CONS:
- `/question` played an equal role in this phase (12 design decisions!) and gets demoted
- Readers scanning headings might not realize `/question` is part of the pre-planning workflow

### Option C: Keep generic heading, add skill callout in subtitle style

```
### 1. Pre-planning: explore before committing to a plan

> Uses `/scratchpad` and `/question`
```

PROS:
- Preserves the conceptual framing ("pre-planning" is a phase, not a skill)
- Subtitle callout adds skill visibility without crowding the heading
- Blockquote renders distinctly on GitHub — easy to scan

CONS:
- Introduces a new formatting pattern (blockquote subtitle) not used in other steps
- Two levels of information in one heading area — slightly more complex visually
- Other steps don't need this because they're 1:1 with a skill

### Option D: Reframe as the `/question` step

`### 1. `/question` — explore before committing to a plan`

PROS:
- `/question` is arguably the more distinctive skill in this phase — scratchpads appear throughout, but the 12-question design session is unique to pre-planning
- Clean single-skill heading

CONS:
- The `<details>` block already showcases `/question` prominently — doubling up in the heading may feel redundant
- `/scratchpad` produced the actual plan artifact that drives everything after
- Less intuitive — "question" as a heading for "planning" is a stretch

## Recommendation

Option A. The pre-planning phase genuinely used both skills as equal partners — `/scratchpad` for the plan document, `/question` for the 12 design decisions that shaped it. Naming both in the heading is accurate and gives readers the full picture when scanning. The slight visual heaviness is a fair tradeoff for not misrepresenting the phase as single-skill.
