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

## Step Tracking

When a scratchpad contains an implementation plan, embed the steps inside a fenced JSON block within the `## Implementation Plan` section. The outer scratchpad remains freeform text; only the steps are structured.

### JSON Schema

```json
{
  "steps": [
    {
      "id": "S001",
      "title": "Add parser module",
      "status": "pending",
      "done_when": "Parser exported and passing unit tests",
      "depends_on": [],
      "files": ["src/parser.ts", "src/index.ts"],
      "tasks": [
        "Create parseInput() function in src/parser.ts",
        "Export from src/index.ts barrel file",
        "Add unit tests in src/__tests__/parser.test.ts"
      ]
    },
    {
      "id": "S002",
      "title": "Wire parser into request handler",
      "status": "pending",
      "depends_on": ["S001"],
      "files": ["src/server.ts"],
      "tasks": [
        "Import parseInput from src/parser.ts",
        "Call parseInput() in handleRequest()"
      ]
    }
  ]
}
```

### Field Reference

- **`id`** — `S001`, `S002`, etc. Zero-padded 3-digit IDs mirroring the `/question` skill's `Q001`/`A001` pattern. Use `S001` as the short form in cross-references.
- **`title`** — Short description of the step.
- **`status`** — `pending` | `in_progress` | `done` | `blocked`. Planning skills always write `"pending"`. Only `/tackle-scratchpad-block` transitions status during execution.
- **`done_when`** — Concrete completion criteria. Optional — omit for self-evident steps.
- **`depends_on`** — Array of step IDs that must be `"done"` first. Empty array means no dependencies.
- **`files`** — Array of file paths this step touches.
- **`tasks`** — Array of concrete action items within the step.
- **`addresses`** — (tackle-pr-comment only) Array of feedback item letters, e.g. `["A", "C"]`.

## Code References

When referencing code in scratchpad content, format all file/line references per the `/code-ref` skill conventions. This makes references clickable when tools like RangeLink are installed.

## Prose Style

Format all prose output per the `/prose-style` skill conventions.

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
