---
name: breadcrumb
description: Drop a timestamped note for the current issue - collected by /finish-issue for PR descriptions
argument-hint: <note text>
allowed-tools: Read, Write, Bash(git branch --show-current), Bash(date *)
---

# Breadcrumb

Drop a timestamped note along your journey through an issue. When you run `/finish-issue`, it follows the trail back — collecting all discoveries, decisions, and reminders.

**Input:** $ARGUMENTS (the note text to record)

## Step 1: Detect Branch Context

Read the current branch:

```bash
git branch --show-current
```

Extract the breadcrumb identifier based on branch pattern:

| Branch pattern | Identifier | Example |
|---|---|---|
| `issues/*` | Issue ID per `/issue-context` rules | `issues/332` → `332` |
| `side-quest/*` | Full slug after `side-quest/` | `side-quest/cleanup-test-mocks` → `cleanup-test-mocks` |

**If branch matches neither pattern:**

- Print: "Not on a work branch. Breadcrumbs require an `issues/*` or `side-quest/*` branch."
- STOP

## Step 2: Validate Input

**If $ARGUMENTS is empty or whitespace:**

- Print: "Usage: /breadcrumb `<note text>`"
- STOP

## Step 3: Append Breadcrumb

**File location:** `.breadcrumbs/<identifier>.md`

Where `<identifier>` is the value extracted in Step 1.

**If file doesn't exist**, create it with header:

- For issues: `# Breadcrumbs for Issue #<identifier>`
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

## Prose Style

Format all prose output per the `/prose-style` skill conventions.

## Step 4: Confirm

Print a brief confirmation:

```text
Breadcrumb dropped in .breadcrumbs/<identifier>.md
```

Do NOT print the full file contents — keep it minimal.
