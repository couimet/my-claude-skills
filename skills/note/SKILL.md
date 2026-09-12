---
name: note
version: 2026.09.08@212eab1
description: Capture a note, finding, or result in a new file under .claude-work/. Lightweight alternative to /scratchpad
argument-hint: <description>
allowed-tools: Read, Write, Bash(*/skills/issue-context/target-path.sh *)
---

# Note

Capture a note, finding, or result in a lightweight file. Use this instead of `/scratchpad` when you need to record something without implementation plans, step tracking, or structured formats.

**Input:** $ARGUMENTS (a short description for the filename)

## Step 1: Resolve the Target Path

Run the path helper:

```bash
~/.claude/skills/issue-context/target-path.sh --type notes --description "$ARGUMENTS"
```

Use the stdout as the full absolute file path. The path is unique and its directory exists, so write the file directly to it. See `/issue-context` for the full contract.

## Step 2: Write the File

See `/pre-write` for the think-before-writing rule: complete all reasoning before writing the first word.

Write the note content to the file. The format is freeform. Structure it however best fits the content being captured. There are no required sections or templates.

**The one rule: each paragraph is ONE continuous line.** No line breaks at 72, 80, or any fixed column. Use line breaks only for structural separation (between paragraphs, around lists, around code blocks). Override your default instinct to wrap.

Formatting: see `/prose-style` for the full hard-wrap rationale and for code-reference and GitHub-reference rules.

### Output Anchors

Format: freeform text.
Length: unlimited.
Perspective: whatever fits the content being captured.

Before printing the path in Step 3, re-read the file and verify no paragraph contains a mid-sentence line break. Rewrite any that do.
Also skim for AI-writing tells: em dashes, filler phrases (in order to, due to the fact that), vague attributions, generic positive conclusions. Rewrite any you find.

## Step 3: Confirm

Print only the absolute filepath, exactly as Step 1 returned it. Do NOT print the file contents.
