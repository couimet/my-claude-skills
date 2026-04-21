---
name: question
version: 2026.04.20.1@efed3d9
description: Create a questions file in .claude-work/questions/ for gathering user input on design decisions. Questions go to file (never terminal) — user edits answers in-file as the single source of truth.
argument-hint: <topic>
allowed-tools: Read, Write, Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Question

Create a questions file in `.claude-work/` for gathering user input.

**Input:** $ARGUMENTS (a short topic description for the filename)

## Output format rule (read before writing anything)

**Every paragraph in the questions file — Context, Options text, Recommendation reasoning, etc. — is ONE continuous line.** No line breaks at 72, 80, or any fixed column. Use line breaks only for structural separation: between questions, around the Options block, between fields. This overrides your default instinct to wrap long prose. See `/prose-style` for the full rationale.

## Core Principle

Questions are NEVER printed in terminal output. They go to a file that the user edits directly. The file is the single source of truth for both questions and answers.

## Step 1: Resolve the Target Path

Run these two commands as parallel tool calls — they are independent.

```bash
skills/issue-context/target-path.sh --type questions --description "$ARGUMENTS"
```

```bash
skills/ensure-gitignore/ensure-gitignore.sh
```

Use the stdout of the first command as the full file path. The script handles branch detection, issue-ID extraction, directory creation, auto-numbering, and slug normalization in one call. On an `issues/<ID>` branch the output is `.claude-work/issues/<ID>/questions/NNNN-<slug>.txt`; otherwise `.claude-work/questions/NNNN-<slug>.txt`.

## File Format

Files use `.txt` extension (not `.md`).

```text
# Question Topic

## Q001: <clear, specific question ending with ?>

Context: <why this matters — what decision it unblocks>

Options:
A) <option> - <tradeoff or implication>
B) <option> - <tradeoff or implication>
C) <option> - <tradeoff or implication>

Recommendation: A - <brief reasoning>

A001: [RECOMMENDED] A

---

## Q002: <clear, specific question ending with ?>

Context: <why this matters — what decision it unblocks>
Depends on: Q001 (explain how Q001's answer affects this question)

Options:
A) <option> - <tradeoff or implication>
B) <option> - <tradeoff or implication>

Recommendation: B - <brief reasoning>

A002: [RECOMMENDED] B

---
```

### Structure Rules

Every question MUST include all fields in this order:

1. **Heading**: `## QNNN:` — use `Q001`, `Q002`, etc. for easy cross-referencing
2. **Context**: Why this matters — what decision it unblocks, what changes based on the answer
3. **Depends on** (optional): Reference earlier questions by ID when the answer affects this question (e.g., `Depends on: Q001`)
4. **Options**: Labeled `A)`, `B)`, `C)` etc. — each with a concise tradeoff. Minimum 2, maximum 5.
5. **Recommendation**: Your recommended option letter with brief reasoning
6. **Answer**: `ANNN: [RECOMMENDED] <letter>` — prefilled with your recommendation

### Answer Acknowledgment

The `[RECOMMENDED]` marker signals this answer was prefilled by Claude and has not been reviewed by the user. The user removes `[RECOMMENDED]` to acknowledge the answer:

- **Unreviewed**: `A001: [RECOMMENDED] A`
- **Acknowledged**: `A001: A` (user agreed with recommendation)
- **Changed**: `A001: B; switched because...` (user chose differently)

When reading answers back, treat any answer still containing `[RECOMMENDED]` as unacknowledged — do not proceed with those decisions without confirming.

### Cross-Referencing

Use `Q001`, `Q002` etc. to reference questions and `A001`, `A002` to reference answers — both within the questions file and from other documents (scratchpads, commit messages, etc.).

## Formatting

See `/prose-style` for hard-wrap and GitHub-reference rules.

## Process

1. Create the file with questions formatted as above
2. **Self-check for hard-wrapping.** Re-read the file. For each Context, Recommendation, and option description, verify the text is a single continuous line. If you find a mid-sentence line break in any of those fields, rewrite as one line. Do not skip this check.
3. Print ONLY the filepath in terminal — nothing else
4. Wait for the user to edit answers in the file
5. The file is the single source of truth — read it back to get answers

## When to Use

- Design decisions that need user input
- Architectural choices with no clear winner
- User-facing behavior where preference matters
- Scope clarification when requirements are ambiguous

## When NOT to Use

- Minor choices with clear best practices (just decide)
- Decisions where the codebase already establishes a clear, consistent pattern to follow
- Information you can verify by reading code or documentation rather than asking
