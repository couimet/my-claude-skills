# my-claude-skills

Claude Code is powerful, but out of the box sessions are ephemeral — context evaporates between tasks, there's no trail of decisions made along the way, and commit messages end up as whatever the AI felt like writing. I built these skills because I wanted Claude to be a structured development partner, not just a code generator.

This is a collection of portable [Claude Code skills](https://code.claude.com/docs/en/skills) that add lightweight workflow conventions to every project I work on. They've been iterated over many real issues, PR reviews, and side-quests. Nothing here is theoretical — I use every one of these daily.

## Installation

```bash
git clone git@github.com:couimet/my-claude-skills.git ~/src/my-claude-skills
~/src/my-claude-skills/install.sh
```

This creates symlinks from `~/.claude/skills/` to the repo, making all skills globally available in every Claude Code project. Skills are the [standard Claude Code extension mechanism](https://code.claude.com/docs/en/skills) — each one is a markdown file with instructions that Claude follows when you invoke it.

### Updating

```bash
cd ~/src/my-claude-skills && git pull && ./install.sh
```

The install script is idempotent — safe to run on every pull. It only creates/updates symlinks; it never deletes non-symlink directories.

## Quick Start

Once installed, try these in any project:

### `/scratchpad` — Create a working document

```
/scratchpad plan the authentication refactor
```

Creates a `.scratchpads/0001-plan-the-authentication-refactor.txt` file with structured step tracking. The file is git-ignored — it's your private workspace.

<details>
<summary>See a real scratchpad from this repo</summary>

```
Issue #10 — Add Meat to README: Enrichment Plan

This scratchpad analyzes the current README state and suggests ways
to enrich issue #10 before implementation.

## Gap Analysis

### What's Missing for Beginners
- No explanation of what Claude Code skills even are
- No "what problem does this solve?" framing
- No gentle walkthrough of a first use

### What's Missing for Advanced Users
- No real-world workflow scenarios showing skills composing together
- No illustration of the full issue lifecycle
...
```

Full file: [demo/real-life/issues-10/0001--scratchpad--0004-readme-enrichment-plan-v0001.txt](demo/real-life/issues-10/0001--scratchpad--0004-readme-enrichment-plan-v0001.txt)

</details>

### `/question` — Gather design decisions

```
/question authentication strategy choices
```

Creates a `.claude-questions/0001-authentication-strategy-choices.txt` with structured Q&A. Claude pre-fills recommendations; you edit answers in-file as the single source of truth.

<details>
<summary>See a real question file from this repo</summary>

```
## Q001: Should the root README be the single comprehensive document,
         or should it stay lean and link to deeper pages?

Context: The current README is 25 lines pointing to skills/README.md.

Options:
A) Single comprehensive README - Everything in one scrollable document.
B) Hub-and-spoke - Root README covers intro, link out for details.
C) Progressive disclosure - Heavy use of GitHub's <details> blocks.

Recommendation: A - A single comprehensive README is the most welcoming.

A001: [RECOMMENDED] A
```

Full file: [demo/real-life/issues-10/0002--question--0001-readme-design-decisions-v0001.txt](demo/real-life/issues-10/0002--question--0001-readme-design-decisions-v0001.txt)

</details>

### `/commit-msg` — Draft a commit message

```
/commit-msg add authentication middleware
```

Creates a `.commit-msgs/0001-add-authentication-middleware.txt` focused on WHY, not WHAT — the diff already shows what changed. You review and commit manually; Claude never auto-commits.

<details>
<summary>See a real commit message from this repo</summary>

```
[docs] Bootstrap demo infrastructure and start-issue plan for README overhaul

Establishes the "eat your own dog food" approach: issue #10's own workflow
becomes the README's walkthrough demo. All ephemeral skill artifacts are
persisted in demo/real-life/issues-10/ with a naming convention that makes
the folder a visual timeline.

Benefits:
- Real artifacts replace fabricated examples
- Chronological folder listing tells the story without opening any file
- TIMELINE.md provides narrative context for the full follow-along
```

Full file: [demo/real-life/issues-10/0010--commit-msg--0001-bootstrap-demo-and-start-issue-v0001.txt](demo/real-life/issues-10/0010--commit-msg--0001-bootstrap-demo-and-start-issue-v0001.txt)

</details>

All working files (`.scratchpads/`, `.claude-questions/`, `.commit-msgs/`, `.breadcrumbs/`) are git-ignored automatically. They're your private workspace — only real code and docs get committed.

## Skills

See [skills/README.md](skills/README.md) for the full inventory and architecture.
