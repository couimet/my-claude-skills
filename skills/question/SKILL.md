OK, give me ---
name: question
description: Create a questions file in .claude-questions/ for gathering user input on design decisions. Questions go to file (never terminal) — user edits answers in-file as the single source of truth.
argument-hint: <topic>
allowed-tools: Read, Write, Glob, Bash(git branch --show-current)

---

# Question

Create a questions file in `.claude-questions/` for gathering user input.

**Input:** $ARGUMENTS (a short topic description for the filename)

## Core Principle

Questions are NEVER printed in terminal output. They go to a file that the user edits directly. The file is the single source of truth for both questions and answers.

## Auto-Numbering

1. Find the highest existing number:
   ```
   Glob(pattern="*.txt", path=".claude-questions/")
   ```
2. Increment by 1, zero-padded to 4 digits (e.g., `0001`, `0042`)
3. If no files exist, start at `0001`

## Naming Pattern

Follow the `/issue-context` skill conventions for directory organization when on an issue branch.

Base pattern: `NNNN-description.txt`

Derive the description slug from $ARGUMENTS (lowercase, hyphens, no special chars).

## File Format

Files use `.txt` extension (not `.md`).

```
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

## Process

1. Create the file with questions formatted as above
2. Print ONLY the filepath in terminal — nothing else
3. Wait for the user to edit answers in the file
4. The file is the single source of truth — read it back to get answers

## When to Use

- Design decisions that need user input
- Architectural choices with no clear winner
- User-facing behavior where preference matters
- Scope clarification when requirements are ambiguous

## When NOT to Use

- Minor choices with clear best practices (just decide)
- Decisions where the codebase already establishes a clear, consistent pattern to follow
- Information you can verify by reading code or documentation rather than asking
