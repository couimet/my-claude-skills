# Issue #10 — Add Meat to README: Timeline

This is a real, unredacted record of how Claude Code skills were used to plan and implement issue #10 on this very repository. Every artifact linked below was generated during the actual workflow — nothing fabricated.

Every numbered file in this folder has a corresponding entry here. Read the folder listing top-to-bottom for the chronological story; read this file for the narrative context behind each artifact.

---

## Phase 1: Pre-Planning (before any branch or formal /start-issue)

### Exchange 1 — The Initial Ask

**2026-02-18 — User prompt (paraphrased from memory):**

The user opened the conversation by asking Claude to look at [github.com/couimet/my-claude-skills/issues/10](https://github.com/couimet/my-claude-skills/issues/10) and build a `/scratchpad` suggesting ways to enrich the issue before implementation. They also asked to use `/question` for improvement ideas. Key context from the prompt: the landing README should be welcoming, provide an intro for beginners, and show advanced examples/scenarios so people can see value in the skills that have been iterated over many times.

<!-- YOUR TERMINAL SNIPPET (optional): paste your actual opening prompt here if you'd like to preserve the exact wording -->

**Claude's response:**

Claude fetched the GitHub issue (which was intentionally bare: "Add meat to readme" with two bullet points about pointing to official skills config and adding a "how I work" section with redacted prompts). In parallel, Claude launched an Explore agent to thoroughly read every skill file, both READMEs, and the install script to understand the full project.

After gathering context, Claude invoked `/scratchpad` and `/question`:

**Artifact produced:**

- [0001--scratchpad--0004-readme-enrichment-plan-v0001.txt](0001--scratchpad--0004-readme-enrichment-plan-v0001.txt) — Initial scratchpad with gap analysis (what's missing for beginners, advanced users, and structurally) and 8 enrichment suggestions: opening hook, quick start, full workflow walkthrough, advanced scenarios gallery, philosophy section, restructured skills reference, official references, and visual aids.

<!-- YOUR TERMINAL SNIPPET (optional) -->

---

### Exchange 2 — 12 Design Questions Created

**2026-02-18 — Claude creates question file**

As part of the same response, Claude created a question file with 12 design decisions (Q001-Q012) covering: information architecture, tone/voice, real vs. fabricated examples, inline samples, reference structure, philosophy section, visual diagrams, section ordering, official references, examples/ directory, customization section, and opening hook style.

**Artifact produced:**

- [0002--question--0001-readme-design-decisions-v0001.txt](0002--question--0001-readme-design-decisions-v0001.txt) — 12 questions with `[RECOMMENDED]` markers (unanswered).

<!-- YOUR TERMINAL SNIPPET (optional) -->

---

### Exchange 3 — User Answers All 12 Questions

**2026-02-18 — User edited `.claude-questions/0001-readme-design-decisions.txt`**

The user answered all 12 questions in-file. Most answers aligned with recommendations, but A003 was a game-changer: the user proposed using the actual current conversation as the demo — "eat your own dog food." Key ideas from A003:

- Leave issue #10 bare as-is, build the full-cycle demo from it
- Use the actual skill invocations from this conversation as the walkthrough
- Persist all ephemeral artifacts in `demo/real-life/issues-10/`
- Capture the conversation as a narrative log
- Introduce an intentional error hoping CodeRabbit catches it to demo `/tackle-pr-comment`

Other notable answers: casual first-person tone (A002), collapsible `<details>` blocks for inline depth (A004), philosophy section with RangeLink/crash-recovery/folder-org bullets (A006), Mermaid diagrams (A007), credit standards rather than pretending to invent anything (A009), encourage PRs not just forks (A011).

**Artifact produced:**

- [0003--question--0001-readme-design-decisions-v0002.txt](0003--question--0001-readme-design-decisions-v0002.txt) — Same 12 questions, now with user's answers filled in.

<!-- YOUR TERMINAL SNIPPET (optional) -->

---

### Exchange 4 — Follow-up Questions on the Demo Approach

**2026-02-18 — Claude creates follow-up question file**

A003's answer was substantial enough to warrant its own question file. Claude created 5 follow-up questions about the demo approach: whether demo/ replaces examples/, versioning scheme, conversation capture method, issue scoping, and workflow mechanics.

**Artifact produced:**

- [0004--question--0002-demo-approach-v0001.txt](0004--question--0002-demo-approach-v0001.txt) — 5 follow-up questions with `[RECOMMENDED]` markers (unanswered).

<!-- YOUR TERMINAL SNIPPET (optional) -->

---

### Exchange 5 — User Answers Demo Follow-ups

**2026-02-18 — User edited `.claude-questions/0002-demo-approach.txt`**

Key decisions: demo/ replaces examples/ entirely (A001), NNNN version suffix format per issue-context conventions (A002), hybrid TIMELINE.md with reconstructed past and ongoing narrative (A003), keep as single issue (A004), copy after each invocation with "Added new file:" messaging (A005).

The user also pointed to [github.com/couimet/rangeLink](https://github.com/couimet/rangeLink) PRs as evidence that CodeRabbit always finds something to nitpick.

**Artifact produced:**

- [0005--question--0002-demo-approach-v0002.txt](0005--question--0002-demo-approach-v0002.txt) — Same 5 questions, now with user's answers.

<!-- YOUR TERMINAL SNIPPET (optional) -->

---

### Exchange 6 — Scratchpad Refined with Full Implementation Plan

**2026-02-18 — Claude updates the scratchpad**

Claude rewrote the main scratchpad incorporating all 17 resolved decisions into a full implementation plan with 7 JSON-tracked steps (S001-S007), README section outline, demo artifact conventions, and assumptions.

**Artifact produced:**

- [0006--scratchpad--0004-readme-enrichment-plan-v0002.txt](0006--scratchpad--0004-readme-enrichment-plan-v0002.txt) — Refined plan with key decisions summary, section outline, and 7-step implementation plan.

<!-- YOUR TERMINAL SNIPPET (optional) -->

---

### Exchange 7 — Protecting Against Context Compaction

**2026-02-18 — User raises context compaction risk**

While reviewing the scratchpad, the user asked what could be done to ensure context compaction wouldn't lose conversation details not yet captured. Claude wrote TIMELINE.md immediately as a protective measure, reconstructing the full conversation from memory. Also backfilled all 6 artifact copies into the demo folder.

At this point, the demo artifacts used a simpler naming convention (no global sequence, no category prefix) — just `<original-filename>-<NNNN>.txt`.

*No new numbered artifact from this exchange — TIMELINE.md itself was the output.*

<!-- YOUR TERMINAL SNIPPET (optional) -->

---

### Exchange 8 — Demo File Naming Convention Discussion

**2026-02-18 — User identifies two naming issues**

The user noticed the demo filenames were missing file-placement category information and the `v` prefix on version suffixes. Claude created a new scratchpad to work through the naming convention.

**Artifact produced:**

- [0007--scratchpad--0005-demo-file-naming-convention-v0001.txt](0007--scratchpad--0005-demo-file-naming-convention-v0001.txt) — Initial proposal: `<category>--<original-filename>-v<NNNN>.<ext>` with double-dash delimiter and `v` prefix.

<!-- YOUR TERMINAL SNIPPET (optional) -->

---

### Exchange 9 — Global Chronological Sequence Added

**2026-02-18 — User suggests global auto-numbering**

The user pointed out that category-first sorting loses the chronological narrative. They proposed prepending a global sequence number so the folder listing matches TIMELINE.md 1-for-1. Claude updated the scratchpad with the final three-part convention.

**Artifact produced:**

- [0008--scratchpad--0005-demo-file-naming-convention-v0002.txt](0008--scratchpad--0005-demo-file-naming-convention-v0002.txt) — Final naming convention: `<NNNN>--<category>--<original-filename>-v<NNNN>.<ext>` with chronological mapping table.

<!-- YOUR TERMINAL SNIPPET (optional) -->

---

### Exchange 10 — Executing the Rename (S001)

**2026-02-18 — Claude executes S001 from scratchpad 0005**

User approved the naming convention. Claude renamed all 6 existing demo files, created the two new scratchpad artifacts (#0007, #0008), rewrote TIMELINE.md with updated links, and updated the main scratchpad's conventions section.

*No new numbered artifact — this exchange updated existing files and TIMELINE.md.*

<!-- YOUR TERMINAL SNIPPET (optional) -->

---

## Phase 2: Formal Issue Workflow

### Exchange 11 — /tackle-scratchpad-block S002 + /start-issue

**2026-02-18 — User invokes `/tackle-scratchpad-block` on S002 of the main plan**

The user ran `/tackle-scratchpad-block .scratchpads/0004-readme-enrichment-plan.txt#L132-L147` to execute S002 ("Create feature branch and formal start-issue flow"). This triggered:

1. Created `issues/10` branch from `origin/main`
2. Invoked `/start-issue` against the GitHub issue, which created the formal implementation plan scratchpad at `.scratchpads/issues/10/0001-start-issue-plan.txt`

The start-issue plan consolidates all 17 resolved design decisions into a clean 6-step implementation plan (S001-S006) specific to the README work. This is the plan that will drive the actual implementation via subsequent `/tackle-scratchpad-block` invocations.

Note: The start-issue plan (6 steps) is a streamlined version of the main plan's S003-S007 (5 steps). The main plan's S001-S002 were infrastructure/setup steps already completed.

**Artifact produced:**

- [0009--scratchpad--0001-start-issue-plan-v0001.txt](0009--scratchpad--0001-start-issue-plan-v0001.txt) — Formal `/start-issue` implementation plan with 6 JSON-tracked steps covering README sections, CodeRabbit demo, and finish-issue wrap-up.

<!-- YOUR TERMINAL SNIPPET (optional) -->

**Artifact also produced:**

- [0010--commit-msg--0001-bootstrap-demo-and-start-issue-v0001.txt](0010--commit-msg--0001-bootstrap-demo-and-start-issue-v0001.txt) — Commit message for the demo bootstrap + start-issue work.

---

## Phase 3: Implementation

### Exchange 12 — /tackle-scratchpad-block S001: README Sections 1-3

**2026-02-18 — User invokes `/tackle-scratchpad-block` on S001 of the start-issue plan**

The user ran `/tackle-scratchpad-block demo/real-life/issues-10/0009--scratchpad--0001-start-issue-plan-v0001.txt#L26-L41` to execute S001 ("Write README sections 1-3: opening hook, installation, quick start"). The code reference points Claude at the exact JSON step block to execute — this precision is central to the `/tackle-scratchpad-block` philosophy: you choose which step to work on, and Claude reads the surrounding plan for context. Claude rewrote README.md from 25 lines to ~120 lines with:

1. **Opening hook** — Problem-statement framing: Claude Code is powerful but sessions are ephemeral, context evaporates, commit messages are arbitrary. These skills add structure.
2. **Installation** — Kept existing content, added inline link to official Claude Code skills docs and a brief explanation of what skills are.
3. **Quick Start** — Three real commands (`/scratchpad`, `/question`, `/commit-msg`) each with a collapsible `<details>` block showing actual output from this repo's demo artifacts.

The `<details>` blocks link to real files in `demo/real-life/issues-10/` — readers can click through to see the full untruncated artifacts.

**Artifacts produced:**

- [0011--readme--README-v0001.md](0011--readme--README-v0001.md) — First version of the rewritten README with sections 1-3.

<!-- YOUR TERMINAL SNIPPET (optional) -->

---

## Phase 4: PR and CodeRabbit (pending)

*This section will be filled in when the PR is created and reviewed.*

---

## Phase 5: Wrap-up (pending — /finish-issue)

*This section will be filled in at the end.*
