---
name: scratchpad
description: Create a working document in .scratchpads/ with auto-numbered filenames. Use for implementation plans, PR descriptions, analysis notes, architecture decisions, GitHub issue drafts, or any temporary working document. Not for questions (use /question), commit messages (use /commit-msg), or permanent docs.
argument-hint: <description>
allowed-tools: Read, Write, Glob, Bash(git branch --show-current)
---

# Scratchpad

Create or update a working document in `.scratchpads/`.

**Input:** $ARGUMENTS (a short description for the filename)

## Directory and Numbering

Follow the `/issue-context` skill to determine the target directory and `NNNN` file sequence number. The base directory is `.scratchpads/`.

## Naming Pattern

The filename is `NNNN-description.txt` where `NNNN` comes from `/issue-context` auto-numbering.

Derive the description slug from $ARGUMENTS (lowercase, hyphens, no special chars).

## File Format

Files use `.txt` extension (not `.md`).

The content is freeform — structure it for the purpose at hand (plan, analysis, PR description, etc.).

## Code References

When referencing code in scratchpad content, format all file/line references per the `/code-ref` skill conventions. This makes references clickable when tools like RangeLink are installed.

## Questions Trigger

If design questions arise while creating or updating a scratchpad:

1. **FIRST** use `/question` to create a questions file and gather user answers
2. Wait for user to fill in answers
3. Then create/update the scratchpad with resolved decisions inlined

The questions workflow lets the user edit answers in-file; the scratchpad captures the resolved state.

## When to Use

- PR descriptions being drafted
- Implementation plans and analysis
- Architecture decision exploration
- GitHub issue drafts
- Any temporary working document

## When NOT to Use

- Questions needing user answers → use `/question`
- Commit messages → use `/commit-msg`
- Permanent documentation → `docs/` or package READMEs
