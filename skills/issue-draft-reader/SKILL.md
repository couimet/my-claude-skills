---
name: issue-draft-reader
version: 2026.09.02@026b73f
user-invocable: false
description: 'Reads a standardized issue draft into front-matter fields, a title, and a body for /create-github-issue and /create-jira-issue, and strips ephemeral local-path references. Auto-consulted by both creation skills.'
allowed-tools: Read, Write, Glob
---

# Issue Draft Reader

Read a standardized issue draft into the pieces an issue-creation skill needs. `/create-github-issue` and `/create-jira-issue` consult it automatically. It is not invoked directly by the user.

A draft is standard when its content opens with a YAML-style `---` front-matter block holding the machine fields, followed by a `#` title heading over a markdown body. Drafts are authored that way by `/draft-issue`. An unstandardized file must pass through `/draft-issue` before a creation skill accepts it.

## Front-Matter Fields

The standard field set, shared by both creation skills:

| Field | Meaning | Reference form |
| --- | --- | --- |
| `target-repo` | Target repository for `/create-github-issue` | `owner/repo` |
| `target-project` | Jira project key for `/create-jira-issue` | `KEY` |
| `issue-type` | Jira issue type | free text |
| `assignee` | Jira assignee | account id, email, or name |
| `like` | Jira ticket to mirror fields from | `KEY-123` |
| `parent` | Parent issue or ticket | full GitHub issue URL, or Jira key |
| `blocked-by` | Dependencies this issue waits on | list of URLs or keys |
| `is-blocking` | Dependencies this issue unblocks | list of URLs or keys |

A creation skill acts on the keys it understands and ignores the rest, so a draft can carry fields for both trackers. The front-matter block is never filed: creation strips it and files the body.

## Step 1: Determine the Input Mode

Determine the input mode from the argument the calling skill passes:

- **File path**: if the argument points to an existing file (any path, any extension or none), treat it as a draft to read.
- **Inline title**: otherwise, treat the entire argument as the issue or ticket title for defaults-only creation. No front matter exists, so no fields resolve, and the calling skill supplies any body.

## Step 2: Validate the Standard and Read the Fields

In file mode, read the file. Its first non-empty line must be the `---` opening fence of a front-matter block, and a matching closing `---` must appear before the body.

If the file has no front-matter block, it is not a standardized draft. STOP the creation flow and print:

```text
Not a standardized draft. Run the conversion command /draft-issue <path> first, then file the returned draft note.
```

Do not guess at title, body, or fields for an unstandardized file. In inline-title mode there is no file to validate, so this step is a no-op.

Read the field lines between the two fences. A `key: value` line is one field. A key with no value, `blocked-by:` or `is-blocking:`, takes the following indented `- value` lines as its list. Skip comment lines that start with `#`. Return every field to the calling skill alongside the title and body.

## Step 3: Extract Title and Body

In file mode, after the closing fence:

- **Title**: the first `#`-level heading (strip the `#` prefix)
- **Body**: everything after the title heading

If no `#` heading exists below the closing fence, the file is not a standardized draft even though it has front matter: STOP and print the same conversion message as Step 2, because a `#` title heading is part of the standard and the title must never be guessed from body content. In inline-title mode the calling skill supplies the title and body, so this step is a no-op.

## Step 4: Sanitize the Body

Strip references to ephemeral local paths that don't exist on the remote tracker:

- `.claude-work/` paths (scratchpads, notes, questions, commit-msgs, breadcrumbs)

Print the list of stripped references so the user can verify nothing important was removed:

```text
Stripped ephemeral references:
- .claude-work/issues/42/scratchpads/0001-plan.txt (line 12)
- .claude-work/issues/42/questions/0001-scope.txt (line 28)
```

If no ephemeral references were found, print:

```text
No ephemeral references found. Body is clean.
```

Formatting: see `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.
