Issue #10 — Add Meat to README: Enrichment Plan

This scratchpad analyzes the current README state and suggests ways to enrich issue #10 before implementation. The goal is to make the landing README welcoming for beginners while showcasing advanced value for experienced Claude Code users.

## Current State

The root README.md is 25 lines — clone, install, and a pointer to skills/README.md. The skills README is a dry inventory table. Neither communicates *why* someone would want these skills, what workflow problems they solve, or what using them feels like in practice.

## Gap Analysis

### What's Missing for Beginners
- No explanation of what Claude Code skills even are or how they work
- No "what problem does this solve?" framing
- No gentle walkthrough of a first use (e.g., "try `/scratchpad my first plan`")
- No visual sense of what the output looks like (sample scratchpad, question file, etc.)
- No explanation of the two-tier architecture in beginner-friendly terms
- No mention of the non-invocable skills that "just work" in the background

### What's Missing for Advanced Users
- No real-world workflow scenarios showing skills composing together
- No day-to-day examples (the issue mentions "redacted/safe prompts from my day-to-day")
- No illustration of the full issue lifecycle: start-issue → tackle blocks → finish-issue
- No examples of side-quest branching during issue work
- No PR comment response workflow example
- No sense of how the step tracking JSON evolves through execution

### What's Missing Structurally
- No link to official Claude Code skills documentation (the issue calls this out explicitly)
- No philosophy/design principles section explaining the choices (user-controls-commits, plan-then-execute, ephemeral-vs-permanent)
- No contributing guidance for people who want to adapt or extend skills
- No changelog or version history summary

## Enrichment Suggestions

### 1. Opening Hook — "What This Is and Why You'd Want It"
A 2-3 paragraph introduction that frames the problem (Claude Code is powerful but unstructured by default) and the solution (these skills add lightweight workflow conventions). Should mention that this is a real, battle-tested set used daily — not a demo project.

### 2. Quick Start for Beginners
A "Your First 5 Minutes" section:
- Install (already exists, keep it)
- Try `/scratchpad plan a widget` — show what gets created
- Try `/question design choices for widget` — show the Q&A format
- Try `/commit-msg add widget parser` — show the commit draft
- Explain: "These files are git-ignored. They're your private workspace."

### 3. The Full Workflow — A Real Scenario
Walk through a complete issue lifecycle using a realistic (but redacted) example:
1. `/start-issue https://github.com/you/project/issues/42` — creates branch, scratchpad with plan
2. Review the plan, answer questions in the question file
3. `/tackle-scratchpad-block .scratchpads/issues/42/0001-plan.txt#L15-L30` — execute first step
4. `/breadcrumb discovered the API changed in v3, had to adapt` — capture a finding
5. `/start-side-quest fix flaky test discovered during work` — branch off, fix, return
6. `/finish-issue` — generates PR description from breadcrumbs and commits

This section is the centerpiece — it shows the skills aren't isolated tools but a connected system.

### 4. Advanced Scenarios Gallery
Short, focused examples for each composite skill showing non-obvious value:
- **PR Comment Triage:** `/tackle-pr-comment` classifies feedback as ACCEPT/IGNORE with reasoning
- **Side-Quest Discipline:** `/start-side-quest` stashes work, branches, and provides return instructions
- **Step Dependencies:** Show a scratchpad with depends_on chains and how blocked status works
- **Breadcrumb → PR:** Show how `/finish-issue` collects breadcrumbs into a PR description

### 5. "How I Work" — Philosophy Section
Explain the design principles:
- **User controls execution:** Claude plans, user reviews, user commits
- **Ephemeral vs. permanent:** Working files are git-ignored; only real code and docs get committed
- **Plan then execute:** Every composite skill stops after planning — implementation is a separate, explicit step
- **Two-tier composition:** Foundation skills are standalone; composite skills orchestrate them by reference
- **No magic:** Skills are just markdown files with instructions — fully readable and forkable

### 6. Skills Reference (Restructured)
Keep the inventory but make it scannable:
- Group by "What You Type" (invocable) vs. "What Works Automatically" (non-invocable)
- Add one-sentence "when to use" for each skill
- Link each skill to its SKILL.md for full documentation
- Add the dependency graph showing how composite skills use foundations

### 7. Official References
- Link to Claude Code skills configuration documentation
- Link to the SKILL.md format specification
- Brief note on how to create your own skills (encourage forking)

### 8. Visual Aids
Consider including:
- A sample scratchpad excerpt showing the hybrid text+JSON format
- A sample question file showing Q001/A001 format
- A diagram or ASCII art showing the two-tier architecture
- A diagram showing the issue lifecycle flow

## Questions to Resolve Before Implementation

See the companion question file for design decisions that would meaningfully change the README structure and content. Key open questions include: tone/voice, how much sample output to inline vs. link, whether to include actual redacted prompts, and the overall section ordering.
