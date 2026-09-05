---
name: question
version: 2026.09.03@a8dc4ea
description: Create a questions file in .claude-work/questions/ for gathering user input on design decisions. Questions go to file (never terminal). The user edits answers in-file as the single source of truth. A bare call delegates the challenge of what to ask to /g2q; --format-only skips the challenge and only creates the file. /g2q emits its questions in dependency waves, each wave its own file, and a paused run is relayed as paused because questions remain held for a later wave.
argument-hint: '[--format-only] <topic>'
allowed-tools: Read, Write, Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Question

Create a questions file in `.claude-work/` for gathering user input.

**Input:** $ARGUMENTS (a short topic description for the filename, optionally prefixed with `--format-only`)

## When to Use

Use `/question` when a design decision needs the user's input captured in a questions file. Two modes:

- **`/question <topic>`** — the default. Delegates the challenge of what to ask to `/g2q`: it grills the topic, drafts the genuinely open questions, and reports back. This is the public entry point for a grilling-informed questions file.
- **`/question --format-only <topic>`** — skips the challenge and only creates the file. Use this when the questions are already decided and you only need `/question`'s path resolution, auto-numbering, and gitignore check. `/g2q` uses this mode after it has grilled.

## When NOT to Use

- Minor choices with clear best practices (just decide)
- Decisions where the codebase already establishes a clear, consistent pattern to follow
- Information you can verify by reading code or documentation rather than asking

These are the negative form of the trigger predicate in `/g2q`, which decides whether a candidate ambiguity is worth asking about.

## Output format rule (read before writing anything)

See `/pre-write` for the think-before-writing rule: complete all reasoning before writing the first word.

**Every paragraph in the questions file (Context, Options text, Recommendation reasoning, Plan impact, etc.) is ONE continuous line.** No line breaks at 72, 80, or any fixed column. Use line breaks only for structural separation: between questions, around the Options block, between fields. This overrides your default instinct to wrap long prose. See `/prose-style` for the full rationale.

## Core Principle

Questions are NEVER printed in terminal output. They go to a file that the user edits directly. The file is the single source of truth for both questions and answers.

## Step 1: Resolve the Target Path (format-only mode only)

Run this step only in format-only mode. In delegation mode, skip it: `/g2q` resolves the path exactly once via `/question --format-only`, so `target-path.sh` is invoked at most once per invocation.

Run these two commands as parallel tool calls. They are independent.

```bash
~/.claude/skills/issue-context/target-path.sh --type questions --description "$ARGUMENTS"
```

```bash
~/.claude/skills/ensure-gitignore/ensure-gitignore.sh
```

Use the stdout of the first command as the full absolute file path. The script handles branch detection, issue-ID extraction, directory creation, auto-numbering, and slug normalization in one call. On an `issues/<ID>` branch the output is an absolute path ending in `/.claude-work/issues/<ID>/questions/NNNN-<slug>.txt`. Otherwise it is an absolute path ending in `/.claude-work/questions/NNNN-<slug>.txt`.

When `$ARGUMENTS` starts with `--format-only`, strip the flag before passing the description to `target-path.sh` so the filename slug derives from the topic only.

## File Format

Files use `.txt` extension (not `.md`).

```text
# Question Topic

## Q001: <clear, specific question ending with ?>

Context: <why this matters and what decision it unblocks>

Options:
A) <option> - <tradeoff or implication>
B) <option> - <tradeoff or implication>
C) <option> - <tradeoff or implication>

Recommendation: A - <brief reasoning>

**Plan impact:** <which steps of the plan or flow change based on the answer>

A001: [RECOMMENDED] A

---

## Q002: <clear, specific question ending with ?>

Context: <why this matters and what decision it unblocks>
Depends on: Q001 (explain how Q001's answer affects this question)

Options:
A) <option> - <tradeoff or implication>
B) <option> - <tradeoff or implication>

Recommendation: B - <brief reasoning>

**Plan impact:** <which steps of the plan or flow change based on the answer>

A002: [RECOMMENDED] B

---
```

### Structure Rules

Every question MUST include all fields in this order:

1. **Heading**: `## QNNN:` use `Q001`, `Q002`, etc. for easy cross-referencing
2. **Context**: Why this matters, what decision it unblocks, what changes based on the answer
3. **Depends on** (optional): Reference earlier questions by ID when the answer affects this question (e.g., `Depends on: Q001`)
4. **Options**: Labeled `A)`, `B)`, `C)` etc., each with a concise tradeoff. Minimum 2, maximum 5.
5. **Recommendation**: Your recommended option letter with brief reasoning
6. **Plan impact**: A `**Plan impact:**` line after the Recommendation explaining which steps of the plan or flow would change based on the answer
7. **Answer**: `ANNN: [RECOMMENDED] <letter>`, prefilled with your recommendation

### Answer Acknowledgment

The `[RECOMMENDED]` marker signals this answer was prefilled by Claude and has not been reviewed by the user. The user removes `[RECOMMENDED]` to acknowledge the answer:

- **Unreviewed**: `A001: [RECOMMENDED] A`
- **Acknowledged**: `A001: A` (user agreed with recommendation)
- **Changed**: `A001: B; switched because...` (user chose differently)

When reading answers back, treat any answer still containing `[RECOMMENDED]` as unacknowledged. Wait for the user to replace `[RECOMMENDED]` with their chosen letter before proceeding.

### Cross-Referencing

Use `Q001`, `Q002` etc. to reference questions and `A001`, `A002` to reference answers, both within the questions file and from other documents (scratchpads, commit messages, etc.).

### Wave Emissions and the Held-Questions Section

When a `/g2q` grilling pass runs in waves, each wave is its own numbered questions file, and a wave may carry extra lines after the last question block. The trailing section appears only when it has content.

A wave that holds questions closes with a `Held:` heading followed by one line per held question naming the question and the answers it waits on. Held questions carry no number: a question is numbered when it is emitted in a later wave, so the sequence is recovered from the highest emitted number in the newest wave file, never from a reserved range.

A wave whose just-answered predecessors made a still-open question moot carries `Retired: <question> - <answer responsible>` lines under the same heading, one per retired question, scoped to that wave. Prior wave files are never edited, so a retired question is explained in the wave that retires it, never silently dropped.

A resume whose answers retire the last held questions emits a terminal wave: a file whose body is only the `Retired:` lines, with no question blocks and no `Held:` section, which the run reads as complete.

The answer-acknowledgment convention applies per wave: the user removes `[RECOMMENDED]` on the newest wave file to answer it, and a paused run's caller resumes grilling for the next wave once those answers are in.

## Formatting

See `/prose-style` for hard-wrap and GitHub-reference rules.

## Process

1. **Delegation mode (no `--format-only`).** Delegate the challenge to `/g2q` with the same topic. Do NOT resolve the target path here (skip Step 1): `/g2q` resolves it exactly once via `/question --format-only` when questions are raised. `/g2q` grills the topic, drafts the questions following the file format above, creates each wave file via `/question --format-only <topic> wave <N>`, using the current wave number, skips file creation only for a first pass that raises nothing, and reports the path plus whether any questions were raised and whether the run is paused. Relay the report: when questions were raised and the run is complete, print ONLY the absolute filepath in terminal. When questions were raised and the run is paused (questions remain held for a later wave), print the absolute filepath and state that the run is paused, so the caller knows a later wave follows this wave's answers. When none were raised, print `No questions raised.` Nothing else, and return here: no questions file exists, so the wait-for-answers step must not run.
2. **Format-only mode (`--format-only`).** Resolve the target path (Step 1, stripping the flag), create the file with a `# <Topic>` heading, print ONLY the absolute filepath in terminal, and return immediately. Nothing else: do NOT wait for answers, since the caller writes the drafted questions into the file.
3. **Wait for answers (delegation mode only, and only when questions were raised).** The file is the single source of truth. Read it back to get answers.
