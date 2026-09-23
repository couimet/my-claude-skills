---
name: question-format
version: 2026.09.21@73231a2
user-invocable: false
description: The questions-file format - question block template, answer region and closer rules, the [RECOMMENDED] acknowledgment gate, wave emission with Held and Retired sections, and the paste-back block. Auto-consulted by any skill that writes or reads a questions file.
allowed-tools:
---

# Question Format

The single home for the questions-file format. `/question` resolves paths and relays, `/g2q` decides what to ask, this skill defines what the file looks like. Files use the `.txt` extension, and every paragraph is one continuous line per `/prose-style`.

## Template

```text
# Question Topic

## Q001: <clear, specific question ending with ?>

Context: <why this matters and what decision it unblocks>

Options:
A) <option> - <tradeoff or implication>
B) <option> - <tradeoff or implication>
C) <option> - <tradeoff or implication>

Recommendation: A - <brief reasoning>

A001: [RECOMMENDED] A
</A001>

---

## Q002: <clear, specific question ending with ?>

Context: <why this matters and what decision it unblocks>
Depends on: Q001 (explain how Q001's answer affects this question)

Options:
A) <option> - <tradeoff or implication>
B) <option> - <tradeoff or implication>

Recommendation: B - <brief reasoning>

A002: B

I switched because the first option assumes the caller holds the questions in context.
</A002>

---

When you have answered every question above, send this to Claude:

/answers-ready <absolute path to this file>

---
```

## Structure rules

Every question carries these fields, in this order:

1. **Heading**: `## QNNN:` using `Q001`, `Q002`, for cross-referencing
2. **Context**: why this matters and what decision it unblocks
3. **Depends on** (optional): earlier question IDs whose answers affect this one
4. **Options**: `A)`, `B)`, `C)`, each with a concise tradeoff. Minimum 2, maximum 5
5. **Recommendation**: the recommended letter with brief reasoning
6. **Answer**: `ANNN: [RECOMMENDED] <letter>`, prefilled with the recommendation
7. **Answer closer**: `</ANNN>` alone on its own line at column zero

Reference questions as `Q001` and answers as `A001`, inside the file and from other documents.

## The answer region

An answer runs from its `ANNN:` opener to its `</ANNN>` closer, and everything between belongs to the user, for as many paragraphs as the reasoning needs.

**Always write the closer**, under every answer. The user never adds one. A closer required only for long answers is the dangerous form: a user writes three paragraphs, does not know a closer was needed, and a reader takes the first line and drops the rest without complaint.

**The opener carries the letter**, which keeps a short answer to one line of typing.

**A closer counts only at column zero, alone on its line.** An indented or mid-line `</A001>` is answer content. The skills document this format, so an answer that quotes a closer while discussing it is a real case.

## Answer acknowledgment

`[RECOMMENDED]` marks an answer prefilled by Claude and not yet reviewed. The user clears it to acknowledge: `A001: [RECOMMENDED] A` unreviewed, `A001: A` acknowledged, `A001: B; switched because...` changed.

**The gate is hard.** A consumer refuses to fold answers while any marker stands, and names the questions still carrying one. A standing marker never means acceptance, and no signal from the user overrides it. Cleared markers are themselves the completion signal, so the format carries no separate ready-state field that could disagree with them.

**A marker counts only in an answer-opener position**, `^A[0-9]{3}: *[RECOMMENDED]`. The token in prose is discussion of the convention, not an unanswered question. Same reasoning as the closer rule.

## Wave emissions, Held and Retired

A `/g2q` pass emits its questions in waves, each wave its own file, and a wave may carry a trailing section when it has content. Prior wave files are never edited, so the newest file is always the state.

A wave that holds questions closes with a `Held:` heading and one line per held question, naming the question and the answers it waits on. Held questions carry no number, so the sequence is recovered from the highest emitted number in the newest file.

A wave whose just-answered predecessors made a still-open question moot carries `Retired: <question> - <answer responsible>` lines under the same heading, scoped to that wave, so a retired question is explained rather than silently dropped.

A resume that retires the last held questions emits a terminal wave: only `Retired:` lines, no question blocks and no `Held:` section, which the run reads as complete.

Acknowledgment applies per wave. The user clears markers on the newest file, and the caller resumes grilling once those answers are in.

## The paste-back block

Every questions file closes with the block shown in the template, placed after the last answer's closer and before any `Held:` section. That is where the user's eye lands when the last answer is written, and it is bounded on both sides so a reader locates and skips it exactly.

The block names the skill rather than a shell command, because a file that carries an executable command trains a reader to run command strings that arrive through a file.

## Reading answers back

Never read a questions file in full to collect its answers. See `/answers-ready`, which owns the extract-and-act contract.
