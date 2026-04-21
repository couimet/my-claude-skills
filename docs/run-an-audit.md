# Run an efficiency audit on this skills collection

This used to be a skill (`/audit-efficiency`). The skill was removed in [issues/120](https://github.com/couimet/my-claude-skills/issues/120) because an independent audit run from a fresh session found the skill itself was a source of bias — the in-repo version auto-loaded into context and steered Claude toward a HIGH/MEDIUM/LOW framing and a pre-picked category list before it got to see the actual state of the collection.

The replacement is this file: a prompt you paste into a fresh Claude Code session. The narrative for why is in [media/2026-04-devto-post-audit-pivot.md](../media/2026-04-devto-post-audit-pivot.md).

## How to run it

1. Open a new Claude Code session in the project root.
2. Run `/clear` as the first command so no prior context primes the answer.
3. Paste the prompt below as the opening message. The only edit you need is the project path in the second paragraph.
4. Read the resulting report cold, in a separate window, before reacting in the chat. Reacting in-chat re-biases Claude for any follow-ups.

## The prompt

> I want an independent audit of a Claude Code skills collection for token efficiency. I am the author of this collection and I have already written a skill called `/audit-efficiency` that performs this kind of analysis, but I want you to NOT use it. I want your own reasoning, your own categories, and your own priorities — not a rerun of my existing framing.
>
> The project root is `/path/to/your/skills`. The skills live in `skills/<name>/SKILL.md`, each with YAML front matter (`name`, `version`, `description`, `user-invocable`, `allowed-tools`) followed by Markdown instructions. Skills marked `user-invocable: false` are "foundation" skills that are not directly invokable but are loaded into context either by explicit `/skill-name` prose references in other skills or by auto-consultation (Claude matches the foundation's `description` against the current task and loads the whole SKILL.md file).
>
> Do not read `skills/audit-efficiency/SKILL.md` until after you have formed your own opinion. If you find yourself about to read it, stop and finish your own analysis first. You can read it at the end as a cross-check.
>
> Do not read the CHANGELOG, the README, or the skills/README.md until after your initial scan — they will bias you toward the author's existing mental model.
>
> Here is the question I want you to answer, in order:
>
> 1. For a Claude Code user who invokes skills like `/start-issue`, `/scratchpad`, `/question`, `/commit-msg`, `/finish-issue`, `/tackle-scratchpad-block`, `/tackle-pr-comment` many times per week, where is token budget being spent unnecessarily on this collection?
> 2. For each finding, estimate how often the overhead is paid (once per session, once per skill invocation, once per skill type, etc.) — frequency matters more than absolute size for ranking.
> 3. Rank findings by your own impact scheme. Do not use HIGH/MEDIUM/LOW if that is what the project's own audit skill uses — pick labels that reflect your actual reasoning.
> 4. For each top-ranked finding, propose at least two alternative fixes and state which you would recommend and why. Include the alternative "do nothing because the cost is acceptable" when it is plausible.
> 5. Separately, identify any anti-patterns you see that are NOT about token efficiency but are about reliability, maintainability, or reviewability — things a fresh reader would flag. Keep this list short; the primary question is efficiency.
> 6. End with: "What question would you have asked me before starting this audit if you could?" — I want to surface gaps in my framing.
>
> Constraints on your method:
>
> - Read SKILL.md files directly. Do not run any of the skills.
> - Use Grep and Glob for structural scans (cross-reference counts, front-matter surveys, line counts). Do not grep for terms you picked up from this prompt — pick your own terms.
> - Do not stop at the obvious. If you see only one category of inefficiency, push yourself to find a second and third.
> - Call out skills that look well-optimized — not just problems. A balanced report is more useful than a hit list.
> - If you discover that my starting hypothesis (DRY-via-cross-references costs tokens) is wrong or weakly supported, say so and explain what the data actually shows.
>
> Output format:
>
> - Write to a single Markdown file in `/tmp/` (pick a timestamped name). Do not write to `.claude-work/` — I want this separate from my usual working files.
> - Lead with a three-sentence executive summary.
> - Include a "Findings" section with your ranked list.
> - Include a "Recommended Next Steps" section with 3-5 concrete actions, each tagged with expected effort (small / medium / large).
> - Include a "What I did not check" section listing anything you deliberately skipped and why.
> - Include the "Question I would have asked" line at the very end.
>
> When you are done, print ONLY the absolute path of the report file. Do not summarize your findings in the chat — I will read the file.

## Why the prompt is shaped this way

Three design choices carry the weight:

1. **Explicit "do not read" list.** Claude's default behavior is to pull in context aggressively. Telling it explicitly to ignore the in-repo audit skill, the CHANGELOG, and the README reduces priming.
2. **Forced alternative-fix reasoning.** Asking for at least two alternatives per finding (including "do nothing") prevents the audit from becoming a rationalization for a predetermined answer.
3. **The "question I would have asked" trailer.** This is the cheapest way to surface a gap in your framing — if Claude had a better audit to run but felt constrained by your phrasing, this is where it says so.

After the report lands: cross-check it against a second audit if you have one (a previous run, another tool, or your own intuition). Where they agree is high-confidence. Where they disagree is where you learn something.

If the report comes back weak, the usual cause is that the prompt was too leading. Strip any language that hints at the answer ("is DRY hurting me?") and try again.
