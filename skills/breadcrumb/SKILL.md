---
name: breadcrumb
version: 2026.06.25@7353cfe
description: Drop a timestamped note for the current issue - collected by /finish-issue for PR descriptions
argument-hint: <note text>
allowed-tools: Read, Write, Bash(git branch --show-current), Bash(date *), Bash(*/skills/auto-number/auto-number.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *), Bash(*/skills/issue-context/claude-work-root.sh *)
---

# Breadcrumb

Drop a timestamped note along your journey through an issue. When you run `/finish-issue`, it follows the trail back, collecting all discoveries, decisions, and reminders.

**Input:** $ARGUMENTS (the note text to record)

## Step 1: Detect Branch Context

Run both commands as parallel tool calls. They are independent:

```bash
git branch --show-current
```

```bash
~/.claude/skills/issue-context/claude-work-root.sh
```

Extract the breadcrumb identifier based on branch pattern:

| Branch pattern | Identifier | Example |
| --- | --- | --- |
| `issues/*` | Issue ID (numeric prefix before `-`/`_`, or full segment after `issues/`) | `issues/332` → `332` |
| `side-quest/*` | Full slug after `side-quest/` | `side-quest/cleanup-test-mocks` → `cleanup-test-mocks` |

**If branch matches neither pattern:**

- Print: "Not on a work branch. Breadcrumbs require an `issues/*` or `side-quest/*` branch."
- STOP

Use the stdout of `claude-work-root.sh` as the base path (e.g., `/Users/x/project/.claude-work`). This script automatically detects git worktrees and returns the shared `.claude-work/` location.

## Step 2: Validate Input

**If $ARGUMENTS is empty or whitespace:**

- Print: "Usage: /breadcrumb `<note text>`"
- STOP

## Step 3: Append Breadcrumb

**File location depends on branch pattern:**

- Issues: `<base>/issues/<ID>/breadcrumb.md`
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

Print a brief confirmation with the file path (the full absolute path from `<base>`):

- Issues: `Breadcrumb dropped in <base>/issues/<ID>/breadcrumb.md`
- Side-quests: `Breadcrumb dropped in <base>/breadcrumb-<slug>.md`

Confirm by printing the path as shown above. Length: one line. Do NOT print the full file contents.

## Formatting

See `/prose-style` for hard-wrap and GitHub-reference rules.
