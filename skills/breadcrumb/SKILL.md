---
name: breadcrumb
version: 2026.09.04@3523c9d
description: Drop a timestamped note for the current issue - collected by /finish-issue for PR descriptions
argument-hint: <note text>
allowed-tools: Read, Write, Bash(git branch --show-current), Bash(date *), Bash(mkdir -p *), Bash(*/skills/auto-number/auto-number.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *), Bash(*/skills/issue-context/branch-issue-id.sh *), Bash(*/skills/issue-context/claude-work-root.sh *), Bash(*/skills/issue-context/get-issue-folder-path.sh *)
---

# Breadcrumb

Drop a timestamped note while working on an issue. When you run `/finish-issue`, it collects all discoveries, decisions, and reminders.

**Input:** $ARGUMENTS (the note text to record)

## Step 1: Detect Branch Context

Run `branch-issue-id.sh` to resolve the issue identifier:

```bash
~/.claude/skills/issue-context/branch-issue-id.sh
```

- **Exit 0** — the current branch matches a configured `branchPatterns` entry (a work branch): the printed identifier is the issue breadcrumb identifier. Resolve the issue folder with `get-issue-folder-path.sh` and record its stdout as the issue `<folder>`:

```bash
~/.claude/skills/issue-context/get-issue-folder-path.sh --id <ID>
```

- **Exit 1** — the branch is not an issue branch. Check for a side-quest branch by running `git branch --show-current`:

```bash
git branch --show-current
```

If the branch starts with `side-quest/`, the identifier is the full slug after `side-quest/` (e.g., `side-quest/cleanup-test-mocks` → `cleanup-test-mocks`). If it matches neither pattern, print: "Not on a work branch. Breadcrumbs require an `issues/*` or `side-quest/*` branch." and STOP.

For a side-quest branch, run `claude-work-root.sh` to resolve the base path:

```bash
~/.claude/skills/issue-context/claude-work-root.sh
```

Use the stdout of `claude-work-root.sh` as the base path (e.g., `/Users/x/project/.claude-work`). This script automatically detects git worktrees and returns the shared `.claude-work/` location. Side-quest breadcrumbs sit flat at `<base>/breadcrumb-<slug>.md`.

## Step 2: Validate Input

**If $ARGUMENTS is empty or whitespace:**

- Print: "Usage: /breadcrumb `<note text>`"
- STOP

## Step 3: Append Breadcrumb

**File location depends on branch pattern:**

- Issues: `<folder>/breadcrumb.md`, where `<folder>` is the stdout from `get-issue-folder-path.sh` in Step 1 (it honors the configured `segment`)
- Side-quests: `<base>/breadcrumb-<slug>.md`

Where `<base>` is the stdout from `claude-work-root.sh`, `<ID>` or `<slug>` is the value extracted in Step 1.

**If file doesn't exist**, create it with `<!-- markdownlint-disable MD013 -->` as the very first line, then the header:

- For issues: `# Breadcrumbs for Issue https://github.com/{owner}/{repo}/issues/{identifier}`
- For side-quests: `# Breadcrumbs for Side-Quest: <identifier>`

**Append the entry:**

```markdown
## <TIMESTAMP>

<note text>
```

Where `<TIMESTAMP>` is the current date/time in format `YYYY-MM-DD HH:MM:SS`.

```bash
date "+%Y-%m-%d %H:%M:%S"
```

## Step 4: Confirm

Print a brief confirmation with the file path (the full absolute path):

- Issues: `Breadcrumb dropped in <folder>/breadcrumb.md`
- Side-quests: `Breadcrumb dropped in <base>/breadcrumb-<slug>.md`

Confirm by printing the path as shown above. Length: one line. Do NOT print the full file contents.

## Formatting

See `/prose-style` for hard-wrap and GitHub-reference rules.
