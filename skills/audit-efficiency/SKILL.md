---
name: audit-efficiency
version: 2026.03.16.2@5c1ef72
description: Audit a skills directory for token-consumption inefficiencies — shell-script candidates, parallelization opportunities, and cross-reference loading overhead. Outputs a structured report with HIGH/MEDIUM/LOW impact ratings.
argument-hint: [skills-dir]
allowed-tools: Read, Glob, Grep
---

# Audit Efficiency

Scan a project's skills directory for token-consumption inefficiencies and produce a structured report. Covers three categories: logic that should be shell-scripted, step sequences that could be parallelized, and cross-reference loading overhead.

**Input:** $ARGUMENTS (optional path to the skills directory; defaults to `skills/`)

## Background

Skills describe algorithms in Markdown and let Claude reason through them each invocation. That works well for decisions and judgment calls, but wastes tokens on deterministic operations — the kind a shell script handles in one Bash call returning a single line of stdout. This skill identifies those operations so they can be offloaded, following the pattern established by `/auto-number` and `/ensure-gitignore`.

## Step 1: Locate SKILL.md Files

Determine the target directory: use `$ARGUMENTS` if provided, otherwise default to `skills/`.

Use Glob to find all `SKILL.md` files:

```text
Glob(pattern="*/SKILL.md", path=<skills-dir>)
```

If no files are found, print: `No SKILL.md files found in <skills-dir>.` and STOP.

Read each SKILL.md file. For large directories (> 15 files), read them in parallel batches.

## Step 2: Shell-Script Candidates

Scan each skill's instruction steps for patterns where Claude is asked to perform deterministic computation that a shell script could handle in one Bash call.

**Pattern A — Read-Check-Append:** Steps that (1) read a file, (2) check for a string or value, and (3) conditionally append or write. The entire operation is deterministic given the inputs.

Examples of this pattern:

- Read `.gitignore`, check for sentinel, append block if missing
- Read a config file, check for a key, add it if absent

**Pattern B — Pure computation:** Steps that ask Claude to count files, find a maximum number, compute a path, or perform arithmetic from file contents.

Examples:

- "Find all files matching `NNNN-*.txt`, extract the highest NNNN, return max+1"
- "Count the lines in FILE and report the total"

**Pattern C — Existence check:** Steps that read a file or directory only to determine whether it exists or contains a specific entry — with no need for the contents otherwise.

Examples:

- "Read `.gitignore` and check if `# sentinel` is present"
- "Read `package.json` to check if a script named `test` exists"

For each finding, record:

- Skill name and file path
- The specific lines or section containing the pattern
- A one-sentence description of the fix (e.g., "Extract to a shell script that reads STDIN and returns 'present' or 'missing'")

## Step 3: Step Sequence Analysis

For each skill, look at the step sequence and identify steps that are declared sequential but have no data dependency between them — meaning they could be issued in a single Claude response (parallel tool calls) instead of sequentially.

**What to look for:**

- Two consecutive steps that each fetch independent data (e.g., "Fetch issue" then "Check current branch" — these could be one response)
- A step that reads context followed by a step that reads different context, with no output from step N feeding into step N+1

**What NOT to flag:**

- Steps where the output of step N is input to step N+1 (genuine data dependency)
- Steps that are already documented as parallel in the skill ("do X and Y in parallel")
- Interactive steps that require user input before the next step can run

For each finding, record:

- Skill name
- The steps that could be parallelized
- The reason they are safe to parallelize (no shared data)

## Step 4: Cross-Reference Loading Overhead

Identify foundation skills (those with an explicit `user-invocable: false` in their front matter, referenced via `/skill-name` in prose). For each, count how many other skills reference it.

**High-overhead pattern:** A foundation skill that:

- Is referenced by many skills (≥ 5)
- Has content that rarely changes (style rules, format conventions)
- Could instead be inlined into CLAUDE.md or directly into each referencing skill — saving one skill-file load per invocation

For each finding, record:

- Foundation skill name and file size (line count)
- Number of skills that reference it
- Assessment: inline vs keep-as-skill (prefer keeping as skill if content is > ~30 lines or is referenced by < 4 skills)

## Step 5: Output Report

Print a structured report. Never hard-wrap prose — each finding is one continuous line.

```text
=== Efficiency Audit: <skills-dir> ===

Skills scanned: N

--- HIGH IMPACT ---

[SHELL-SCRIPT] skill-name/SKILL.md
  Pattern: <A|B|C> — <what the skill does that a script could do>
  Fix: <one-sentence description of the script to write>

--- MEDIUM IMPACT ---

[PARALLEL] skill-name/SKILL.md
  Steps: <Step N> and <Step M> are independent
  Safe because: <reason>

--- LOW IMPACT ---

[CROSS-REF] foundation-skill-name/SKILL.md (N lines)
  Referenced by: N skills
  Assessment: <inline | keep — reason>

--- SUMMARY ---

Shell-script candidates: N  (eliminate file reads in Claude's context)
Parallelization opportunities: N  (reduce round-trips)
Cross-reference overhead: N  (low-impact style/convention files)

No findings → Skills are already well-optimized for token efficiency.
```

If a category has no findings, omit it from the report.

## When to Use

- After adding new skills to a project — catch inefficiencies before they compound
- Before performance-sensitive rollouts where token cost matters
- As part of periodic skill maintenance (e.g., every 10+ skill additions)
- When onboarding a new project to the skills infrastructure — establish a baseline

## Quality Checklist

Before finishing:

- [ ] All SKILL.md files in the target directory were read
- [ ] Each finding references specific skill names and sections
- [ ] Impact ratings reflect actual frequency (HIGH = runs on every invocation, LOW = runs rarely)
- [ ] Report is actionable — each finding has a clear, concrete fix
