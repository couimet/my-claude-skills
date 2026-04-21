---
title: "I thought I was DRY-ing. I may have been double-paying."
published: false
description: "A second look at my Claude Code skills: half-finished refactors may cost more than the duplication they were trying to eliminate. Here's what an independent audit surfaced, and what I changed as a result."
tags: ai, claudecode, productivity, devtools
cover_image:
---

## Something was off

A few weeks after publishing [From Vide Coding to Supercharged Vibe Guiding](https://dev.to/couimet/from-vide-coding-to-supercharged-vibe-guiding-6nm), I landed [pull/121](https://github.com/couimet/my-claude-skills/pull/121) — a follow-up refactor that made `/scratchpad`, `/question`, and `/commit-msg` "self-contained" by inlining a foundation skill's logic into each of them. I was expecting lighter sessions afterwards. I couldn't tell if I got them. The next refactor on my list was "inline more of these foundations," and I caught myself about to make the same bet twice — without ever having checked whether the first one paid off.

My theory at that point, the one driving both refactors, was that the foundation skills were what cost too much. `/code-ref` for code-link format, `/github-ref` for issue-URL format, `/issue-context` for figuring out which directory a scratchpad should go in — all auto-consulted by Claude constantly. The working assumption was that the cross-references themselves were the tax. Inline the rules, kill the foundations, buy the tokens back.

My hypothesis may have had the cost in the wrong place. At least, an independent audit thought it did.

## So I let another Claude run the audit

Doing the audit myself would have confirmed my bias. So I opened a fresh Claude Code session, told it explicitly not to run my own `/audit-efficiency` skill, not to read my README or CHANGELOG, and asked six specific questions:

1. Where is token budget being spent unnecessarily?
2. How often is each overhead paid (once per session, once per invocation, once per skill type)?
3. Rank the findings with your own labels. Don't use the HIGH/MEDIUM/LOW my existing audit skill uses.
4. For each top finding, propose at least two fixes including "do nothing."
5. Separately, flag anti-patterns about reliability and maintainability, not just efficiency.
6. End with: "What question would you have asked me before starting this audit if you could?"

The full prompt, verbatim, with its design rationale, is in the collapsible block below.

<details>
<summary><b>Click to expand: the full audit prompt</b></summary>

Paste the block below as the opening message of a fresh Claude Code session (run `/clear` first so nothing from your previous work primes the answer). The only change you need is the project path in the second paragraph.

---

I want an independent audit of a Claude Code skills collection for token efficiency. I am the author of this collection and I have already written a skill called `/audit-efficiency` that performs this kind of analysis, but I want you to NOT use it. I want your own reasoning, your own categories, and your own priorities — not a rerun of my existing framing.

The project root is `/path/to/your/skills`. The skills live in `skills/<name>/SKILL.md`, each with YAML front matter (`name`, `version`, `description`, `user-invocable`, `allowed-tools`) followed by Markdown instructions. Skills marked `user-invocable: false` are "foundation" skills that are not directly invokable but are loaded into context either by explicit `/skill-name` prose references in other skills or by auto-consultation (Claude matches the foundation's `description` against the current task and loads the whole SKILL.md file).

Do not read `skills/audit-efficiency/SKILL.md` until after you have formed your own opinion. If you find yourself about to read it, stop and finish your own analysis first. You can read it at the end as a cross-check.

Do not read the CHANGELOG, the README, or the skills/README.md until after your initial scan — they will bias you toward the author's existing mental model.

Here is the question I want you to answer, in order:

1. For a Claude Code user who invokes skills like `/start-issue`, `/scratchpad`, `/question`, `/commit-msg`, `/finish-issue`, `/tackle-scratchpad-block`, `/tackle-pr-comment` many times per week, where is token budget being spent unnecessarily on this collection?
2. For each finding, estimate how often the overhead is paid (once per session, once per skill invocation, once per skill type, etc.) — frequency matters more than absolute size for ranking.
3. Rank findings by your own impact scheme. Do not use HIGH/MEDIUM/LOW if that is what the project's own audit skill uses — pick labels that reflect your actual reasoning.
4. For each top-ranked finding, propose at least two alternative fixes and state which you would recommend and why. Include the alternative "do nothing because the cost is acceptable" when it is plausible.
5. Separately, identify any anti-patterns you see that are NOT about token efficiency but are about reliability, maintainability, or reviewability — things a fresh reader would flag. Keep this list short; the primary question is efficiency.
6. End with: "What question would you have asked me before starting this audit if you could?" — I want to surface gaps in my framing.

Constraints on your method:

- Read SKILL.md files directly. Do not run any of the skills.
- Use Grep and Glob for structural scans (cross-reference counts, front-matter surveys, line counts). Do not grep for terms you picked up from this prompt — pick your own terms.
- Do not stop at the obvious. If you see only one category of inefficiency, push yourself to find a second and third.
- Call out skills that look well-optimized — not just problems. A balanced report is more useful than a hit list.
- If you discover that my starting hypothesis (DRY-via-cross-references costs tokens) is wrong or weakly supported, say so and explain what the data actually shows.

Output format:

- Write to a single Markdown file in `/tmp/` (pick a timestamped name). Do not write to `.claude-work/` — I want this separate from my usual working files.
- Lead with a three-sentence executive summary.
- Include a "Findings" section with your ranked list.
- Include a "Recommended Next Steps" section with 3-5 concrete actions, each tagged with expected effort (small / medium / large).
- Include a "What I did not check" section listing anything you deliberately skipped and why.
- Include the "Question I would have asked" line at the very end.

When you are done, print ONLY the absolute path of the report file. Do not summarize your findings in the chat — I will read the file.

---

Three design choices matter and are worth calling out in case you want to adapt the prompt:

1. **Explicit "do not read" list.** Claude's default behavior is to pull in context aggressively. Telling it explicitly to ignore `/audit-efficiency`, CHANGELOG, and README reduces priming.
2. **Forced alternative-fix reasoning.** Asking for at least two alternatives per finding (including "do nothing") prevents the audit from becoming a rationalization for a predetermined answer.
3. **The "question I would have asked" trailer.** This is the cheapest way to surface a gap in the framing — if Claude had a better audit to run but felt constrained by my phrasing, this is where it says so.

After the report lands: read it cold in a separate window before reacting. Reacting in the chat re-biases Claude for any follow-up questions. Then cross-check against your own `/audit-efficiency` output (if you have one). Where they agree is high-confidence; where they disagree is where you learn something.

</details>

Claude dropped a timestamped report in `/tmp/`. I read it cold. The executive summary opened with:

> The largest recurring cost in this collection is a self-inflicted duplication of branch-parsing + filename logic inlined into `scratchpad`, `question`, and `commit-msg`.

The day before, I'd refactored those three skills to make them "self-contained" — taken about 35 lines of branch-parsing Markdown out of a shared foundation and pasted the same block into each caller. The idea was to stop paying for the foundation's auto-consultation. What actually happened: the foundation kept auto-consulting anyway (its description line advertised itself for exactly that workflow), the same logic was now sitting in three places, and the copies had already started drifting. The foundation's examples list didn't match the inlined copies and I hadn't noticed. So I had two copies of drifting logic and, if the audit's cost model is right, was paying for both.

## My hypothesis was backwards

I'd gone in assuming DRY-via-cross-references was the tax. The audit's sharper version was more like: *half-finished migrations can cost tokens, and deterministic logic in Markdown tends to cost tokens whether it's DRY or not.* That's a working theory, not a measurement — but it's a theory I was already primed to believe once the drift was in front of me.

The audit pointed at two skills it thought were well-shaped — `/auto-number` and `/ensure-gitignore`. Both are foundation skills whose SKILL.md just documents a shell-script contract. The script does the work. Claude calls it and reads one line of stdout. Zero reasoning burned per invocation.

That was the pattern I should have been trying to extend. With the audit in hand, [pull/121](https://github.com/couimet/my-claude-skills/pull/121) looks like the wrong direction — it added more Markdown where, in retrospect, a shell script fits better.

## What the audit found

Findings in my paraphrase of the audit, ranked by how often it thought the cost was paid:

**F1, per-invocation bleed.** The branch-parsing + filename block inlined into `/scratchpad`, `/question`, and `/commit-msg`. Paid every time any of them fires, plus transitively when `/start-issue`, `/tackle-scratchpad-block`, `/finish-issue`, and `/tackle-pr-comment` invoke them.

**F2, per-session surtax.** A three-line "Output Format" epilogue (hard-wrap rule, code-reference rule, GitHub-URL rule) copy-pasted into 11 skills. Two existing foundations (`/code-ref`, `/github-ref`) already covered the same rules.

**F3, structural debt.** `/issue-context` was in a halfway state. Its content had drifted from the inlined copies. A direction had to be picked and finished.

**F4, per-session surtax.** The two longest skill descriptions (`/scratchpad` at 316 chars, `/tackle-scratchpad-block` at 275) loaded into the catalog on every session, even when neither was invoked.

**F5, structural debt verging on bleed.** The step-JSON schema redrawn in five places instead of once.

## The pivot

Before any edits, I worked through six scoping questions in a `/question` file and had the Claude session read them back. One question carried most of the weight: pick *delete-and-script*, *delete-and-inline-more*, *restore-the-foundation*, or *status quo* for `/issue-context`.

I picked the script route. I'd already done it twice. `/auto-number` collapses "scan this directory, find the highest number, add one, zero-pad it" into one Bash call. `/ensure-gitignore` collapses "read the file, check for the sentinel, append if missing" the same way. "Read the branch, extract the issue ID, decide where the file goes, slugify the description, and auto-number it" is the same shape of problem.

I called it `target-path.sh`. One call, one line of stdout:

```bash
skills/issue-context/target-path.sh --type scratchpads --description "audit follow-up"
# → .claude-work/issues/120/scratchpads/0003-audit-follow-up.txt
```

Each of `/scratchpad`, `/question`, and `/commit-msg` dropped from a roughly 45-line Step 1 block to this:

```markdown
Run these two commands as parallel tool calls. They are independent.

- skills/issue-context/target-path.sh --type <type> --description "$ARGUMENTS"
- skills/ensure-gitignore/ensure-gitignore.sh

Use the stdout of the first command as the full file path.
```

The `/issue-context` foundation went from 118 lines of branch-parsing prose to 30 lines that just document the script's contract.

For F2, I folded the hard-wrap rule plus the two reference-format rules into a single new `/prose-style` foundation. Then I deleted the epilogues from all 11 callers and replaced each with a one-line pointer: `Formatting: see /prose-style`. The standalone `/code-ref` and `/github-ref` foundations got folded into `/prose-style` too, then deleted. Side effect: a dangling symlink at `~/.claude/skills/prose-style` that had been pointing at a non-existent directory for months finally had something to point at. I hadn't noticed it was broken.

F4 (descriptions) and F5 (JSON schema redrawn) were one-shot edits. Shrink two descriptions. Replace three inline JSON blocks with references to the authoritative schema in `/scratchpad`.

## What this might save in tokens

Counting SKILL.md content only, the before state was roughly 25,600 tokens and the after state is roughly 21,500. About 4,100 tokens lighter, call it 16%. Treat every token count here as a ~4-chars-per-token ballpark, not a microbenchmark.

The static diff is the part I can actually count. Everything beyond that is arithmetic on the audit's cost model, not a measurement — token consumption is hard to predict when you're not deep in how these systems load context. So take what follows as "if the audit is roughly right, this is what the math would look like."

On a typical full-time coding day I run this loop 25+ times: plan via `/scratchpad`, surface a design question via `/question` when something needs one, tackle a block, draft a `/commit-msg`. That's only about three cycles an hour. When I'm iterating on small pieces, I easily hit 10 cycles an hour. By lunchtime I've already blown past what used to feel like a full day's worth of context.

If the audit's model holds, each cycle was spending around 140 tokens of branch-parsing Markdown re-reasoned per `/scratchpad` call, the same pattern on `/question` and `/commit-msg`, plus the `/issue-context` foundation body pulled in by description match whenever any of them fired. Call it 500 to 1,000 tokens per cycle in duplicated logic.

Multiply by 25 cycles and the refactor might buy back somewhere in the tens of thousands of tokens a day. Double that on a heavy iteration day. The 4,100 tokens I shaved off the static diff is the boring headline; the number that might actually change my workday is closer to 25,000 to 50,000 tokens not being burned on the same deterministic logic over and over. Would I have noticed that in practice? Honestly, I don't know. The real move — the one I should have started with — is to measure often and keep optimizing for whatever actually shows up.

## What I'm taking away

"DRY is good" and "DRY costs tokens" feel like slogans that don't quite capture what I ran into. What I'm starting to think matters more is whether the logic you're trying to deduplicate is deterministic. When it is, my bet is Markdown's the wrong container — a script that returns one line of stdout fits the shape better, and lets Claude spend its reasoning on the parts that need it. The three scripts carrying the load here (`auto-number.sh`, `ensure-gitignore.sh`, and now `target-path.sh`) all fit that shape.

The halfway migration is the one the audit saved me from. My previous refactor inlined three skills and left the foundation in place, and I'd have kept maintaining both without realizing the shape was broken. Committing to either direction would probably have been cheaper than the in-between state I shipped.

One more thing about the audit itself. If I'd run it myself I'd have confirmed my hypothesis and doubled down on inlining — the same move that caused the problem in the first place. Pointing a fresh Claude session explicitly at what *not* to look at was the cheapest way I had to step outside my own framing. Obvious in hindsight. Wasn't at the time.

Which leads to the last decision in this refactor: I deleted my own `/audit-efficiency` skill. Once the cold audit clearly produced a stronger report, keeping the biased version around made it likely I'd reach for it next time. The prompt from this post replaces it at [docs/run-an-audit.md](https://github.com/couimet/my-claude-skills/blob/431fabf3bc1b0de184da89b9fc911f3eab8d8bef/docs/run-an-audit.md) — a file you paste from, not a skill you invoke. That's the whole operational artifact now.

## If you want to try this

The prompt is in the [repo](https://github.com/couimet/my-claude-skills/blob/431fabf3bc1b0de184da89b9fc911f3eab8d8bef/docs/run-an-audit.md) and up above in the collapsible block. Steal either copy.

If you've built your own Claude Code skills and you're curious whether your collection is heavier than it needs to be, the thing I'd try first is running that audit against them in a fresh session. Tell Claude not to use your own audit skill if you have one — or delete yours too. Read the report cold before you react. The fix might not be more DRY — it might not even be moving from prose to script. Your audit could land somewhere completely different from mine.

*Written alongside [the refactor PR itself](https://github.com/couimet/my-claude-skills/pull/122) using the same skills it describes.*
