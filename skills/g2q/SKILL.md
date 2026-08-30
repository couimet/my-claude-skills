---
name: g2q
version: 2026.08.30@7b2f220
description: Grill a topic or working document and emit the genuinely open ambiguities as a /question-format questions file. /question delegates its challenge here; /start-issue and /tackle-pr-comment gate plan production on it.
argument-hint: <topic-or-path>
user-invocable: true
allowed-tools: Read, Write, Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Grill to Questions

Grill a topic or a working document and turn the genuinely open ambiguities into a `/question`-format questions file. This is the shortcut for "run grilling on this and give me the questions as a `/question` file": invoke `/g2q <topic-or-path>` directly, or reference it from a composite skill after it drafts a plan.

**Input:** $ARGUMENTS (a topic to grill, or a path to a working document)

## When to Use

- Directly, as `/g2q <topic>`: challenge a plan, design, or idea and collect the open questions in `/question` format without writing a long prompt.
- Referenced by `/start-issue` and `/tackle-pr-comment` after they draft a plan or analysis, to surface ambiguities before the working document is finalized.
- Consulted by `/question` for the challenge half of its job: a bare `/question <topic>` delegates the challenge here, then formats the result via `/question --format-only`.

## Trigger Predicate

This skill decides which ambiguities are worth asking about. Ask when the answer changes which steps run, their order, or the files they touch, and no precedent settles it; default to asking when the candidate fails the precedent test and passes the user-facing test, because asking costs the user one file edit and a short answer while a wrong assumption costs plan rework.

Run each candidate decision through the checklist below while grilling. The four bullets operationalize the trigger predicate rather than adding new gates.

- Does the answer change which steps run, their order, or the files touched?
- Is there a direct precedent (schema, template, existing file, prior issue) that settles it?
- Is the decision user-facing (naming, defaults, approval gates, deliverable location)?
- Would guessing wrong mean rework of the plan, not just a detail?

Fallback rule: when a question-worthy decision is skipped for a reason, record it in the plan's Assumptions Made section with that reason. Never drop it silently.

Worked example: while planning the `/release-article` skill (issue #228), where the article draft lives before approval looked like a minor location default. Two defensible readings exist. Drafts start in `.claude-work/` working documents with real files written only after approval. Or the release workflow's own template names a `media/` file as the deliverable, and its constraint targets modifying existing files, not creating the new draft. The answer changes which steps run and where the deliverable lands. It is user-facing (approval gates, deliverable location), and no precedent settles it. It failed the precedent test and passed the user-facing test, so it crossed the bar. The plan skipped it anyway. The question was later confirmed worth asking.

## Method

The grilling approach comes from `/grilling`: map the content as a design tree of decisions, work the frontier of questions whose prerequisites are settled, and give a recommended answer for each. In this skill the interview is a single non-interactive content pass: the grilling targets the content, not the user. When `/grill-me` or `/grilling` is installed, treat its instructions as the method source; the inline description here keeps the skill working when they are not.

1. **Read the input.** If `$ARGUMENTS` is a path to an existing file, read it in full. Otherwise treat it as a topic and grill the content the user's message provides around it.

2. **Run the grilling pass.** Enumerate the decisions and claims in the content. For each, adversarially check for unstated assumptions, gaps, weak reasoning, and open ambiguities. Work the design tree until every branch is visited and the frontier is empty. Run each candidate ambiguity through the trigger predicate above: a decision a precedent settles is not a question, so record it as an assumption in the caller's plan instead. Facts you can look up yourself are never questions: find them rather than asking the user.

3. **Draft the questions.** For each genuinely open ambiguity, draft a `/question`-format question following `/question`'s file format and structure rules exactly (see `/question`): the format has exactly one home, there. Only questions whose answers would change the plan or flow belong in the file.

4. **Create the questions file.** Run `/question --format-only <topic>` with a topic derived from the input (it owns path resolution, auto-numbering, and the gitignore check), then write the drafted questions into the returned path following `/question`'s format. The `--format-only` flag tells `/question` the challenge has already happened here and it should only create the file, which breaks the otherwise circular `/question` <-> `/g2q` delegation. After writing, self-check for hard-wrapping: each Context, Recommendation, and option description must be a single continuous line; rewrite any mid-sentence line break. Skim for AI-writing tells (em dashes, filler phrases, vague attributions, generic positive conclusions) and rewrite any you find.

5. **Report.** Print the absolute path to the questions file, and state whether any questions were raised, so composite skills can gate plan production on the answers. When the call came through `/question`, that report is relayed to the caller as just the filepath.

## Formatting

See `/prose-style` for hard-wrap and reference rules, and `/question` for the questions-file format and the answer-acknowledgment convention.
