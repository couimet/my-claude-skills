---
name: question
version: 2026.09.16@ae50bfe
description: Create a questions file for gathering user input on design decisions. Questions go to a file, never the terminal.
argument-hint: '[--format-only] <topic>'
allowed-tools: Read, Write, Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/question/extract-answers.sh *), Bash(*/skills/prose-style/check-prose.sh *)
---

# Question

Create a questions file in `.claude-work/` for gathering user input. The file format lives in `/question-format`. This skill resolves the path and relays the result.

**Input:** $ARGUMENTS (a short topic description for the filename, optionally prefixed with `--format-only`)

## Core Principle

Questions are NEVER printed in terminal output. They go to a file the user edits directly, and that file is the single source of truth for both questions and answers.

## When to Use

- **`/question <topic>`** — the default. Delegates the challenge of what to ask to `/g2q`, which grills the topic and drafts the genuinely open questions.
- **`/question --format-only <topic>`** — skips the challenge and only creates the file. Use when the questions are already decided and you need path resolution, file naming, and the gitignore check. `/g2q` uses this mode after it has grilled.

## When NOT to Use

- Minor choices with clear best practices (just decide)
- Decisions where the codebase already establishes a clear, consistent pattern
- Information you can verify by reading code or documentation rather than asking

These are the negative form of the trigger predicate in `/g2q`.

## Output format rule (read before writing anything)

See `/pre-write` for the think-before-writing rule: complete all reasoning before writing the first word. Every paragraph in the questions file is ONE continuous line, with line breaks only for structural separation. See `/prose-style`.

## Step 1: Resolve the Target Path (format-only mode only)

Run this step only in format-only mode. In delegation mode `/g2q` resolves the path exactly once through `/question --format-only`, so `target-path.sh` runs at most once per invocation.

Run the path helper:

```bash
~/.claude/skills/issue-context/target-path.sh --type questions --description "$ARGUMENTS"
```

Use the stdout as the full absolute file path. The path is unique and its directory exists, so write the file directly to it. See `/issue-context` for the contract.

When `$ARGUMENTS` starts with `--format-only`, strip the flag before passing the description to `target-path.sh` so the filename slug derives from the topic only.

## Process

1. **Delegation mode (no `--format-only`).** Delegate the challenge to `/g2q` with the same topic, and do NOT resolve the target path here. `/g2q` grills, drafts the questions per `/question-format`, creates each wave file through `/question --format-only <topic> wave <N>`, skips file creation only for a first pass that raises nothing, and reports back. Relay that report. Nothing else: print only the absolute filepath when questions were raised and the run is complete; print the filepath and state that the run is paused when questions remain held for a later wave; print `No questions raised.` when none were raised, and return without waiting for answers, because no file exists.
2. **Format-only mode (`--format-only`).** Resolve the target path (Step 1, stripping the flag), create the file with a `# <Topic>` heading, print ONLY the absolute filepath, and return immediately. Do NOT wait for answers: the caller writes the drafted questions into the file.
3. **Wait for answers (delegation mode only, and only when questions were raised).** Collect them through `/answers-ready`, which owns the extract-and-act contract. Never read the file in full.

## Formatting

See `/question-format` for the file format, `/prose-style` for hard-wrap and GitHub-reference rules.
