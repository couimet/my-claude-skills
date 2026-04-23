---
name: scratchpad
version: 2026.04.20.1@a34fc99
description: Create an auto-numbered working document in .claude-work/scratchpads/ — implementation plans, PR descriptions, analysis notes, architecture decisions, issue drafts.
argument-hint: <description>
allowed-tools: Read, Write, Glob, Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Scratchpad

Create or update a working document in `.claude-work/`.

**Input:** $ARGUMENTS (a short description for the filename)

## Output format rule (read before writing anything)

**Every paragraph in the scratchpad is ONE continuous line.** No line breaks at 72, 80, or any fixed column. Use line breaks only for structural separation: between paragraphs, before/after lists, around code blocks, between sections. This overrides your default instinct to wrap long prose. See `/prose-style` for the full rationale.

## Step 1: Resolve the Target Path

Run these two commands as parallel tool calls — they are independent.

```bash
~/.claude/skills/issue-context/target-path.sh --type scratchpads --description "$ARGUMENTS"
```

```bash
~/.claude/skills/ensure-gitignore/ensure-gitignore.sh
```

Use the stdout of the first command as the full file path. The script handles branch detection, issue-ID extraction, directory creation, auto-numbering, and slug normalization in one call. On an `issues/<ID>` branch the output is `.claude-work/issues/<ID>/scratchpads/NNNN-<slug>.txt`; otherwise `.claude-work/scratchpads/NNNN-<slug>.txt`.

## File Format

Files use `.txt` extension (not `.md`).

The content is freeform — structure it for the purpose at hand (plan, analysis, PR description, etc.).

## Step Tracking

When a scratchpad contains an implementation plan, embed the steps inside a fenced JSON block within the `## Implementation Plan` section. The outer scratchpad remains freeform text; only the steps are structured.

### JSON Schema

```json
{
  "finish_issue_on_complete": false,
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

Top-level fields (siblings of `steps`):

- **`finish_issue_on_complete`** — Boolean, default `false` (omit to default). When `true`, `/tackle-scratchpad-block` invokes `/finish-issue` automatically after all steps reach `"done"`. Only `/start-issue` and `/start-side-quest` set this to `true` — they mark the scratchpad as the primary issue deliverable. Every other skill that creates scratchpads (ad-hoc `/scratchpad`, `/tackle-pr-comment`, CI fix scratchpads) omits it.

Step-level fields (inside each `steps` entry):

- **`id`** — `S001`, `S002`, etc. Zero-padded 3-digit IDs mirroring the `/question` skill's `Q001`/`A001` pattern. Use `S001` as the short form in cross-references.
- **`title`** — Short description of the step.
- **`status`** — `pending` | `in_progress` | `done` | `blocked`. Planning skills always write `"pending"`. Only `/tackle-scratchpad-block` transitions status during execution.
- **`done_when`** — Concrete completion criteria. Recommended for implementation plans. Omit only for steps where completion is self-evident (e.g., "Delete file X"). A concrete criterion here helps `/tackle-scratchpad-block` confirm the step is truly done.
- **`depends_on`** — Array of step IDs that must be `"done"` first. Empty array means no dependencies.
- **`files`** — Array of file paths this step touches.
- **`tasks`** — Array of concrete action items within the step.
- **`addresses`** — (tackle-pr-comment only) Array of feedback item letters, e.g. `["A", "C"]`.

## After writing: self-check for hard-wrapping

Before reporting the filepath back to the user, re-read the scratchpad you just wrote. For each paragraph in the body (text between blank lines, outside code blocks, tables, and lists), verify it is a single continuous line. If you find a mid-sentence line break, rewrite that paragraph as one line. Do not skip this check — wrapped prose is the most common failure mode for skill-generated files.

## Formatting

See `/prose-style` for code-reference and GitHub-reference rules. The hard-wrap rule is covered above.

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
