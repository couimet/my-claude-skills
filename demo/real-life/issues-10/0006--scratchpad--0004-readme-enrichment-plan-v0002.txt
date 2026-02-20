Issue #10 — Add Meat to README: Refined Implementation Plan

Resolved decisions from .claude-questions/0001-readme-design-decisions.txt and .claude-questions/0002-demo-approach.txt.

## Summary

Rewrite the landing README as a single comprehensive document with casual first-person voice. The centerpiece is a real "eat your own dog food" demo: we use our actual conversation and issue #10 itself as the walkthrough, persisting all ephemeral artifacts in `demo/real-life/issues-10/` with NNNN-suffixed versioned filenames. A TIMELINE.md narrates the flow. The README links into the demo folder for collapsible full-context examples. We run the full skill lifecycle (start-issue → tackle blocks → breadcrumbs → finish-issue) and let CodeRabbit trigger a /tackle-pr-comment demo naturally.

## Key Decisions (from Q&A)

- **Single comprehensive README** (Q001/A001) — everything in one scrollable document
- **Casual, first-person voice** (Q002/A002) — "I built these because..."
- **Real artifacts from this conversation** (Q003/A003) — no fabrication, full transparency
- **Abbreviated inline + collapsible details** (Q004/A004) — `<details>` blocks for depth, no separate examples/ directory
- **"What You Type" vs. "What Works Automatically"** (Q005/A005) — two-group reference structure
- **Prominent philosophy section** (Q006/A006) — with RangeLink bias, crash recovery, folder-based organization as key bullets
- **Mermaid diagram first** (Q007/A007) — pivot to ASCII if needed
- **Hook → Install → Quick Start → Full Workflow → Philosophy → Reference → Contributing** (Q008/A008)
- **Inline + collected official references** (Q009/A009) — credit standards, don't pretend to have invented anything
- **demo/ replaces examples/** (Q010 resolved by Demo Q001/A001)
- **Brief "Making These Your Own" section** (Q011/A011) — encourage PRs over just forking
- **Problem-statement opening** (Q012/A012) — no fabricated before/after that won't age well
- **NNNN suffix versioning** (Demo Q002/A002) — e.g., `0004-readme-enrichment-plan-0001.txt`
- **TIMELINE.md with prepared user blocks** (Demo Q003/A003) — reconstructed for past, hybrid going forward
- **Single issue scope** (Demo Q004/A004) — demo and README are inseparable
- **Copy after each invocation** (Demo Q005/A005) — "Added new file: <filename>" messaging

## Demo Artifact Conventions

All artifacts persisted in `demo/real-life/issues-10/`.

Naming: `<original-filename>-NNNN.<ext>` where NNNN is a zero-padded sequence scoped per original file.

Examples:
- First version of scratchpad: `0004-readme-enrichment-plan-0001.txt`
- After plan update: `0004-readme-enrichment-plan-0002.txt`
- First question file: `0001-readme-design-decisions-0001.txt`
- After answers filled: `0001-readme-design-decisions-0002.txt`

TIMELINE.md lives at `demo/real-life/issues-10/TIMELINE.md` and is updated (not versioned) since it's the narrative spine.

## README Section Outline

### 1. Opening Hook (problem statement)
Claude Code is powerful but unstructured by default — sessions are ephemeral, context is lost between tasks, commit messages are generic, and there's no trail of decisions made along the way. These skills add lightweight workflow conventions that make Claude a structured development partner.

### 2. Installation
Keep existing content, add brief mention of what Claude Code skills are with inline link to official docs.

### 3. Quick Start — "Your First 5 Minutes"
Three commands to try: `/scratchpad`, `/question`, `/commit-msg`. Show abbreviated output inline with `<details>` blocks expanding to full examples from `demo/real-life/issues-10/`.

### 4. See It In Action — The Full Workflow
The centerpiece. Walk through issue #10's own lifecycle:
1. `/start-issue` — creates branch, scratchpad with implementation plan
2. Review plan, answer questions
3. `/tackle-scratchpad-block` — execute steps iteratively
4. `/breadcrumb` — capture discoveries
5. (Optional) `/start-side-quest` — branch for orthogonal fix
6. `/tackle-pr-comment` — respond to CodeRabbit feedback
7. `/finish-issue` — generate PR description

Each step links to the real versioned artifact in demo/. Mermaid diagram at the top of this section showing the lifecycle flow.

### 5. Why I Built These — Design Philosophy
5-8 bullet points including:
- **Files over chat** — As the author of RangeLink, I'm biased toward precise file references. Skills produce navigable files instead of ephemeral chat output.
- **Crash-proof context** — Work files survive IDE crashes. Status tracking in scratchpads means you can dive back in without reconstructing state.
- **Organized, not scattered** — Folder-based hierarchy (`.scratchpads/issues/42/`) beats flat `~/.claude/plans/` for lookup and search.
- **User controls execution** — Claude plans, user reviews, user commits. No auto-commits, no surprise pushes.
- **Ephemeral vs. permanent** — Working files are git-ignored. Only real code and docs get committed.
- **Plan then execute** — Every composite skill stops after planning. Implementation is a separate, explicit step.
- **No magic** — Skills are just markdown files. Fully readable, forkable, and PR-able.

### 6. Skills Reference
Two groups:

**What You Type** — table of 9 invocable skills with `/command` syntax and one-liner.
**What Works Automatically** — table of 4 non-invocable skills with when they activate.

Link to skills/README.md for architecture details and step tracking format.

### 7. Making These Your Own
Brief paragraph: fork the repo, edit SKILL.md files, re-run install.sh. Encourage PRs for improvements that benefit everyone.

### 8. Resources
Collected links to:
- Official Claude Code skills documentation
- SKILL.md format specification
- Claude Code documentation
- This repo's skills/README.md for architecture details

## Implementation Plan

```json
{
  "steps": [
    {
      "id": "S001",
      "title": "Bootstrap demo infrastructure and backfill artifacts",
      "status": "pending",
      "done_when": "demo/real-life/issues-10/ exists with all prior artifacts versioned and TIMELINE.md reconstructed for conversation so far",
      "depends_on": [],
      "files": [
        "demo/real-life/issues-10/TIMELINE.md",
        "demo/real-life/issues-10/0004-readme-enrichment-plan-0001.txt",
        "demo/real-life/issues-10/0004-readme-enrichment-plan-0002.txt",
        "demo/real-life/issues-10/0001-readme-design-decisions-0001.txt",
        "demo/real-life/issues-10/0001-readme-design-decisions-0002.txt",
        "demo/real-life/issues-10/0002-demo-approach-0001.txt",
        "demo/real-life/issues-10/0002-demo-approach-0002.txt"
      ],
      "tasks": [
        "Create demo/real-life/issues-10/ directory",
        "Copy initial scratchpad (before Q&A) as 0004-readme-enrichment-plan-0001.txt",
        "Copy current scratchpad (this file, post-refinement) as 0004-readme-enrichment-plan-0002.txt",
        "Copy question file #1 as created (blank answers) as 0001-readme-design-decisions-0001.txt",
        "Copy question file #1 with answers as 0001-readme-design-decisions-0002.txt",
        "Copy question file #2 as created (blank answers) as 0002-demo-approach-0001.txt",
        "Copy question file #2 with answers as 0002-demo-approach-0002.txt",
        "Write TIMELINE.md reconstructing the conversation from the start (Option A for past events)",
        "Include prepared <!-- YOUR TERMINAL SNIPPET (optional) --> blocks at each exchange point in the timeline"
      ]
    },
    {
      "id": "S002",
      "title": "Create feature branch and formal start-issue flow",
      "status": "pending",
      "done_when": "On issues/10 branch with /start-issue scratchpad created and copied to demo/",
      "depends_on": ["S001"],
      "files": [
        ".scratchpads/issues/10/0001-start-issue-plan.txt"
      ],
      "tasks": [
        "Create issues/10 branch from origin/main",
        "Run /start-issue against https://github.com/couimet/my-claude-skills/issues/10",
        "Copy resulting scratchpad to demo/ with -0001 suffix",
        "Update TIMELINE.md with this step"
      ]
    },
    {
      "id": "S003",
      "title": "Write the README — sections 1-3 (hook, install, quick start)",
      "status": "pending",
      "done_when": "README.md has opening hook, installation, and quick start sections with collapsible detail blocks",
      "depends_on": ["S002"],
      "files": ["README.md"],
      "tasks": [
        "Write problem-statement opening hook",
        "Update installation section with inline link to official Claude Code skills docs",
        "Write Quick Start section with 3 example commands",
        "Add <details> blocks with full output excerpts linking to demo/ artifacts",
        "Use /tackle-scratchpad-block to execute this step",
        "Copy updated README to demo/ as readme-0001.md",
        "Use /commit-msg for this block, copy to demo/",
        "Update TIMELINE.md"
      ]
    },
    {
      "id": "S004",
      "title": "Write the README — section 4 (full workflow with Mermaid diagram)",
      "status": "pending",
      "done_when": "README.md has 'See It In Action' section with Mermaid lifecycle diagram and step-by-step walkthrough linking to demo/ artifacts",
      "depends_on": ["S003"],
      "files": ["README.md"],
      "tasks": [
        "Create Mermaid diagram showing issue lifecycle flow",
        "Write walkthrough narrative using issue #10's own artifacts",
        "Link each step to versioned files in demo/real-life/issues-10/",
        "Add <details> blocks for expanded artifact views",
        "Use /tackle-scratchpad-block, /commit-msg, copy to demo/",
        "Update TIMELINE.md"
      ]
    },
    {
      "id": "S005",
      "title": "Write the README — sections 5-8 (philosophy, reference, contributing, resources)",
      "status": "pending",
      "done_when": "README.md has philosophy bullets, two-group skills reference, making-your-own section, and collected resources with official links",
      "depends_on": ["S004"],
      "files": ["README.md"],
      "tasks": [
        "Write philosophy section with RangeLink, crash-proof, folder-org bullets",
        "Write two-group skills reference (What You Type / What Works Automatically)",
        "Write Making These Your Own paragraph encouraging PRs",
        "Write Resources section with official Claude Code links",
        "Credit standards appropriately throughout (A009)",
        "Use /tackle-scratchpad-block, /commit-msg, copy to demo/",
        "Update TIMELINE.md"
      ]
    },
    {
      "id": "S006",
      "title": "Introduce intentional error for CodeRabbit demo",
      "status": "pending",
      "done_when": "PR created with a subtle but real error that CodeRabbit is likely to catch (grammar, style, or structural issue)",
      "depends_on": ["S005"],
      "files": ["README.md"],
      "tasks": [
        "Introduce a subtle error (grammar, inconsistent formatting, or similar) that CodeRabbit would flag",
        "Push branch and create PR",
        "Wait for CodeRabbit review",
        "Use /tackle-pr-comment on the CodeRabbit feedback",
        "Copy all PR-comment artifacts to demo/",
        "Update TIMELINE.md"
      ]
    },
    {
      "id": "S007",
      "title": "Wrap up with /finish-issue",
      "status": "pending",
      "done_when": "/finish-issue generates PR description, all demo artifacts collected, TIMELINE.md complete",
      "depends_on": ["S006"],
      "files": [
        "demo/real-life/issues-10/TIMELINE.md"
      ],
      "tasks": [
        "Run /finish-issue",
        "Copy generated PR description scratchpad to demo/",
        "Finalize TIMELINE.md with complete narrative",
        "Review all demo/ artifacts for completeness and coherence",
        "Update README section 4 links if any artifact filenames changed during the process"
      ]
    }
  ]
}
```

## Assumptions

- Issue #10 stays bare on GitHub (as stated in A003) — the demo shows the full workflow starting from that minimal issue.
- CodeRabbit is active on this repo and will review PRs automatically. If not, we adapt the /tackle-pr-comment demo (A004 suggests looking at rangeLink PRs for reference).
- The initial scratchpad (0004-readme-enrichment-plan) was created before the issue branch, so it lives at the root .scratchpads/ level. Once we /start-issue, new scratchpads go in .scratchpads/issues/10/.
- TIMELINE.md is the one file we update in place (not versioned) since it's the narrative spine, not a skill artifact.

## Pre-Implementation Task for User

Before S001 begins: consider copying the opening terminal exchange (your initial prompt and my first response) from the Claude Code terminal. This becomes the opening of TIMELINE.md. I'll reconstruct the narrative for the full conversation so far, but authentic terminal snippets at the start would set the tone. I'll leave prepared blocks in TIMELINE.md for you to paste into.
