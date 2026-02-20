# Demo Protocol

A reference for producing traceable, "show your work" demos that capture every state change as a versioned artifact with a living narrative timeline.

## Why This Exists

Claude Code skills are powerful but invisible -- users install them, run them, and get output, but they never see how skills compose across a real workflow. A README can describe the theory, but showing the actual messy, iterative process of building something is far more convincing.

This protocol was developed during [PR #11](https://github.com/couimet/my-claude-skills/pull/11) on this repository, where we used the skills to enrich their own README ("eat your own dog food"). Over 30+ exchanges, the protocol evolved from ad-hoc file copying into a rigorous system with naming conventions, versioning rules, and hard-earned lessons about what happens when you try to maintain a chronological record alongside active development.

The result: a `demo/real-life/issues-10/` folder with 55+ numbered artifacts and a `TIMELINE.md` that reads like a narrative walkthrough of the entire session. Readers can follow the story top-to-bottom, click through to any artifact, and see exactly what Claude produced at each step.

## Who This Is For

- **Claude** -- follow this protocol when the user asks to build a demo. It encodes conventions that took 30+ exchanges to stabilize.
- **Humans** -- understand how the demo folder is structured and why certain files look the way they do.
- **Reviewers (human or bot)** -- know what to flag and what to skip. The "Review Guidance" section at the end explains which files are living documents and which are frozen history.

---

## Protocol Overview

The demo protocol sits on top of normal skill workflows. After each exchange (a skill invocation, user correction, or significant event), you:

1. **Do the real work** -- run the skill, make the edit, answer the question
2. **Snapshot the output** -- copy each changed working file to the demo folder with the correct naming convention
3. **Update TIMELINE.md** -- append an exchange entry with date, command, narrative, and artifact links
4. **Verify the count** -- keep the "Final Artifact Count" footer accurate

The protocol does not change how skills work. It adds an artifact-capture layer after each step.

---

## Demo Folder Structure

Each demo lives in its own folder under `demo/`. The folder name carries semantic meaning chosen by the user:

```text
demo/
  real-life/
    issues-10/
      TIMELINE.md
      0001--scratchpad--0004-readme-enrichment-plan-v0001.txt
      0002--question--0001-readme-design-decisions-v0001.txt
      ...
```

The user specifies the demo folder path at the start of the session. Convention suggestions:

- `demo/real-life/<issue-slug>/` -- captures an actual issue workflow
- `demo/tutorial/<topic>/` -- a guided walkthrough for teaching
- `demo/walkthrough/<feature>/` -- step-by-step feature showcase

---

## Naming Convention

Every artifact in the demo folder follows this pattern:

```text
<NNNN>--<category>--<original-filename>-v<VVVV>.<ext>
```

### Fields

| Field | Description | Example |
| ----- | ----------- | ------- |
| `NNNN` | Global chronological sequence number across all artifact types | `0042` |
| `category` | The working-file category the artifact came from | `scratchpad`, `commit-msg`, `question`, `readme`, `gitignore` |
| `original-filename` | The source file's name without path or extension | `0004-readme-enrichment-plan` |
| `VVVV` | Version number for this specific source file | `v0001`, `v0002` |
| `ext` | File extension matching the source | `.txt`, `.md` |

### Rules

- **Global sequence is append-only.** Each new artifact gets the next number. Never reuse or skip numbers.
- **Version numbers track the source file.** The first time `0004-readme-enrichment-plan` is copied, it gets `v0001`. The next copy of the same source file gets `v0002`, regardless of how many other artifacts were created in between.
- **Double-dash delimiter** (`--`) separates the three naming components. Single dashes appear within component values (e.g., `readme-enrichment-plan`).
- **The folder listing tells the story.** Sorting by filename produces a chronological narrative that matches TIMELINE.md 1-for-1.

### Category Reference

| Category | Source location | When to snapshot |
| -------- | --------------- | ---------------- |
| `scratchpad` | `.scratchpads/` | After creating or updating a scratchpad |
| `commit-msg` | `.commit-msgs/` | After creating a commit message file |
| `question` | `.claude-questions/` | After creating or receiving answers to questions |
| `readme` | `README.md` | After modifying the README |
| `gitignore` | `.gitignore` | After modifying .gitignore |

Add new categories as needed. The category should match the working-file type, not the skill that produced it.

---

## TIMELINE.md

The timeline is the narrative spine of the demo. It lives at the root of the demo folder and connects every artifact to the story of what happened and why.

### Structure

```markdown
# Issue #N -- Title: Timeline

Brief intro explaining what this timeline captures.

---

## Phase N: Phase Title

### Exchange N -- Title

**<date> -- <command or trigger>**

<1-3 sentence narrative>

**Artifacts produced:**

- [filename](filename) -- description

---
```

### Exchange Anatomy

Every exchange entry has these parts:

1. **Heading** -- `### Exchange N -- <descriptive title>`. Sequential numbering, no gaps.
2. **Date and command** -- the exact date and the skill invocation or user action that triggered this exchange. For skill invocations, capture the full command including code references (e.g., `/tackle-scratchpad-block demo/real-life/issues-10/0049--scratchpad--...-v0002.txt#L59-L70`).
3. **Narrative** -- 1-3 sentences explaining what happened and why. Written in past tense. Focus on decisions, discoveries, and outcomes -- not mechanical descriptions of what files changed.
4. **Artifacts produced** -- bulleted list linking to each demo artifact created during this exchange, with a brief description.

### Phase Grouping

Group exchanges into phases that reflect the natural workflow stages. Common phases:

- **Pre-Planning** -- exploration before any branch or formal plan
- **Formal Issue Workflow** -- `/start-issue` and branch creation
- **Implementation** -- `/tackle-scratchpad-block` iterations
- **PR and CodeRabbit** -- push, review, and feedback cycles
- **Wrap-up** -- `/finish-issue` and final documentation

### Footer

End with a count: `## Final Artifact Count\n\nNN numbered files + TIMELINE.md.`

Update this after every exchange.

---

## Versioned Artifact Pairs

When a source file is snapshotted more than once, the versions form an intentional before/after pair:

- **v0001** is the "before" state
- **v0002** is the "after" state

The diff between v0001 and v0002 should show only the meaningful change that occurred during that exchange. For scratchpads with JSON step tracking, a typical diff is a status transition: `"status": "pending"` in v0001 and `"status": "done"` in v0002.

### Why This Matters

Reviewers (and bots like CodeRabbit) will see v0001 in isolation and flag "stale" fields. A `"pending"` status in v0001 is not stale -- it is the accurate starting state before the step was executed. The pair tells the story; neither version tells it alone.

---

## Protocol Rules

These emerged from real mistakes during PR #11 and are now encoded as protocol requirements.

### 1. Frozen Snapshot Principle

Demo artifacts are historical records. They capture a file exactly as it existed at a specific point in time. **Never modify a snapshot**, even if it contains typos, broken links, or style issues. When something needs fixing, the fix goes in the living source file; the snapshot stays as-is.

This follows the same principle as git commits -- you don't rewrite history to fix a typo in a past commit message.

**Consequence for reviewers:** Feedback targeting frozen snapshots (prose polish, formatting, stale-looking fields) should be declined. The snapshot is accurate to its moment in time.

### 2. "Altering the Past" Consistency

Sometimes a correction requires updating demo artifacts -- for example, when an ACCEPT/IGNORE decision changes after artifacts were already snapshotted. When this happens, update ALL versions of the affected source file so diffs between v0001 and v0002 show only the expected change (like a status transition), not a massive content rewrite.

This is the exception to the frozen snapshot principle. It applies only when the original decision was wrong and the correction must flow through all versions to keep diffs clean.

### 3. Ephemeral Source Awareness

Working files (`.scratchpads/`, `.claude-questions/`, `.commit-msgs/`) are git-ignored and never committed directly. Their demo snapshot copies ARE committed. Since the original source is ephemeral, prose polish or formatting feedback on snapshot copies is not actionable -- there is no living source file to apply changes to.

### 4. No Forward References in Timeline

Each exchange reads as a standalone entry written at the time it happened. Never annotate Exchange N with "(reverted in Exchange N+2)" or similar forward-looking notes. This breaks chronological flow and creates maintenance burden.

If a later exchange corrects an earlier one, the later exchange's narrative explains what it fixed. The earlier exchange stands as originally written.

### 5. Exchange Numbering Is Append-Only and Gapless

If an exchange is removed (e.g., because it described work that was reverted), renumber subsequent exchanges to close the gap. Never leave holes in the sequence.

### 6. Capture the Command Verbatim

Every exchange that runs a skill records the exact invocation, including full file paths and line-range references. This lets readers reproduce the step and understand exactly what Claude was pointed at.

Commands in TIMELINE.md should always reference demo folder paths (e.g., `demo/real-life/issues-10/0049--scratchpad--...`), not ephemeral `.scratchpads/` paths. Even if the user originally invoked the skill using a `.scratchpads/` path, normalize it to the demo artifact path in TIMELINE.md.

### 7. Split Analysis and Execution Exchanges

When a workflow involves distinct analysis and execution phases (e.g., `/tackle-pr-comment` followed by `/tackle-scratchpad-block`), record them as separate exchanges. This mirrors the actual workflow where the user reviews the analysis before approving execution.

### 8. One Exchange Per Meaningful State Change

An exchange represents a single meaningful event: a skill invocation, a user correction, a design decision. Do not combine unrelated changes into one exchange. If the user provides feedback and Claude applies it, that is one exchange (the user's feedback is the trigger; the application is the response).

---

## Workflow: Starting a Demo

When the user asks to build a demo:

1. **Confirm the demo folder path.** Ask the user where artifacts should go (e.g., `demo/real-life/issues-10/`). The path carries semantic meaning.

2. **Create TIMELINE.md** at the root of the demo folder with the intro header, a Phase 1 section, and the Final Artifact Count footer.

3. **Establish the sequence.** If artifacts already exist in the folder, find the highest `NNNN` and continue from there. If starting fresh, begin at `0001`.

4. **After every exchange**, follow the capture cycle:
   - Copy each changed working file to the demo folder with the correct name
   - Append the exchange entry to TIMELINE.md
   - Update the artifact count footer
   - Verify the new artifacts are linked in the exchange entry

---

## Workflow: Snapshotting an Artifact

1. **Determine the global sequence number.** Find the highest existing `NNNN` in the demo folder and add 1.

2. **Determine the version number.** Search the demo folder for existing copies of the same source file. If `0006--scratchpad--0004-readme-enrichment-plan-v0002.txt` exists, the next version is `v0003`.

3. **Copy the file.** The content is an exact copy of the source -- no modifications, no formatting changes, no "cleanup."

4. **For scratchpad versioned pairs:** If the scratchpad tracks step status via JSON, ensure v0001 shows the "before" state (e.g., `"pending"`) and the new version shows the "after" state (e.g., `"done"`). If you are creating v0001 mid-execution, save it before making changes.

---

## Workflow: Handling Corrections

When something needs to be fixed in a previously snapshotted artifact:

1. **Fix the living source file** (the working scratchpad, README, etc.).
2. **Do NOT modify the existing snapshot.** It is a frozen record.
3. **Create a new snapshot** with the next version number showing the corrected state.
4. **Exception: "Altering the past"** -- if the correction changes a decision that flowed through multiple versions (e.g., flipping an ACCEPT to IGNORE), update all versions to keep diffs clean. This is rare and should be noted in the TIMELINE exchange that performs the correction.

---

## Review Guidance

This section helps reviewers (human or bot) focus their efforts on what matters.

### Living Documents (Review Normally)

These files are actively maintained and should be reviewed for accuracy, quality, and consistency:

- **TIMELINE.md** -- do the exchange narratives match what the artifacts actually show?
- **README.md** (or whatever end product the demo builds) -- quality, formatting, content correctness
- **Cross-artifact consistency** -- do artifact pairs tell a coherent story? If a snapshot claims something happened but TIMELINE tells a different story, that is a real bug.

### Frozen Artifacts (Skip Review)

These files are historical records and should not receive feedback:

- **Demo snapshots** (any `NNNN--category--*` file) -- typos, style issues, formatting, stale-looking fields in versioned pairs are all accurate to their moment in time
- **Ephemeral-source snapshots** -- working scratchpads (`.scratchpads/`), questions (`.claude-questions/`), and commit messages (`.commit-msgs/`) are git-ignored originals whose demo copies cannot be retroactively fixed

### What IS a Real Bug

- A TIMELINE exchange narrative that contradicts its linked artifacts
- Missing artifacts (referenced in TIMELINE but not in the folder)
- Broken links in TIMELINE to artifacts that don't exist
- Artifact count footer that doesn't match the actual file count
- Version numbering gaps or duplicates

---

## Lessons from PR #11

These are specific situations that arose during the first demo and shaped the rules above. They serve as worked examples for future demos.

### CodeRabbit and Frozen Snapshots

CodeRabbit flagged typos, style issues, and "stale" fields in demo snapshots across four review passes. After we posted a [protocol explanation comment](https://github.com/couimet/my-claude-skills/pull/11#issuecomment-3934534495), CodeRabbit [acknowledged the protocol](https://github.com/couimet/my-claude-skills/pull/11#issuecomment-3934547347) and saved learnings to avoid flagging frozen artifacts in the future. Key takeaway: educate automated reviewers early in the PR to reduce noise.

### The Overreach Incident

After an AI reviewer flagged prose issues in demo snapshots, we initially modified the snapshots, then realized this violated the frozen snapshot principle. We reverted the changes and "altered the past" by removing the exchange that described the overreach. This taught two lessons: (1) never polish frozen artifacts based on reviewer feedback, and (2) when you remove an exchange, renumber to close the gap and don't leave a narrative about the removal.

### The "Altering the Past" Edge Case

When a review caused us to flip an ACCEPT decision to IGNORE (removing S003 from a scratchpad), we had to update all existing versioned copies of that scratchpad so diffs between v0001 and v0002 showed only status transitions, not content rewrites. This is the most complex protocol operation and requires updating multiple files atomically.

### Stale Narrative After Corrections

After correcting artifacts 0047-0050 to reflect a changed ACCEPT/IGNORE split, we missed updating the TIMELINE exchange narrative that described the original plan. CodeRabbit correctly caught this inconsistency. Lesson: when correcting artifacts, always check that the TIMELINE narrative matches the corrected state.

### Path Normalization

Early exchanges used `.scratchpads/` paths in TIMELINE skill invocations. Since the demo tracks progress through demo folder artifacts, TIMELINE should always reference `demo/real-life/issues-10/` paths. Normalize any ephemeral paths that slip through.

---

## Future Considerations

This protocol is currently manual. If a second demo confirms the pattern generalizes, a `/demo-protocol` skill could automate the artifact-capture layer. The most valuable automation targets:

- **Naming convention enforcement** -- the global sequence and version numbering were the top source of manual errors
- **TIMELINE.md maintenance** -- appending exchange entries with correct artifact links
- **Artifact count tracking** -- keeping the footer accurate

The narrative portion of each exchange will likely remain human-authored or human-edited, since it requires judgment about what matters and why.

The protocol has real value -- it produced a compelling, traceable demo that would be hard to recreate without it. But the narrow use case (demo content production, not daily development) and a single data point (PR #11) argue for waiting. The recommended path: follow this reference manually on a second demo, note where automation would help most, and build the skill afterward with two real-world examples to design against. This avoids over-engineering while preserving the knowledge gained.
