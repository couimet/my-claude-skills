---
name: issue-draft-reader
version: 2026.10.22@b3b9515
user-invocable: false
description: 'Reads a standardized issue draft into front-matter fields, a title, and a body for /create-github-issue and /create-jira-issue, strips ephemeral local-path references, and asks whether to inline or remove each local-only file reference. Auto-consulted by both creation skills.'
allowed-tools: Read, Write, Glob, AskUserQuestion, Bash(git ls-files *)
---

# Issue Draft Reader

Read a standardized issue draft into the pieces an issue-creation skill needs. `/create-github-issue` and `/create-jira-issue` consult it automatically. It is not invoked directly by the user.

A draft is standard when its content opens with a YAML-style `---` front-matter block holding the machine fields, followed by a `#` title heading over a markdown body. Drafts are authored that way by `/draft-issue`. An unstandardized file must pass through `/draft-issue` before a creation skill accepts it.

## Front-Matter Fields

The standard field set, shared by both creation skills:

| Field            | Meaning                                      | Reference form                     |
| ---------------- | -------------------------------------------- | ---------------------------------- |
| `target-repo`    | Target repository for `/create-github-issue` | `owner/repo`                       |
| `target-project` | Jira project key for `/create-jira-issue`    | `KEY`                              |
| `issue-type`     | Jira issue type                              | free text                          |
| `assignee`       | Jira assignee                                | account id, email, or name         |
| `like`           | Jira ticket to mirror fields from            | `KEY-123`                          |
| `parent`         | Parent issue or ticket                       | full GitHub issue URL, or Jira key |
| `blocked-by`     | Dependencies this issue waits on             | list of URLs or keys               |
| `is-blocking`    | Dependencies this issue unblocks             | list of URLs or keys               |
| `jira-fields`    | Jira fields set by display name              | indented `Name: value` lines       |

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

Read the field lines between the two fences. A `key: value` line is one field. A key with no value, `blocked-by:` or `is-blocking:`, takes the following indented `- value` lines as its list. A key with no value whose following indented lines are `Name: value` pairs, such as `jira-fields:`, reads as a map from each name to its value. Skip comment lines that start with `#`. Return every field to the calling skill alongside the title and body.

## Step 3: Extract Title and Body

In file mode, after the closing fence:

- **Title**: the first `#`-level heading (strip the `#` prefix)
- **Body**: everything after the title heading

If no `#` heading exists below the closing fence, the file is not a standardized draft even though it has front matter: STOP and print the same conversion message as Step 2, because a `#` title heading is part of the standard and the title must never be guessed from body content. In inline-title mode the calling skill supplies the title and body, so this step is a no-op.

## Step 4: Sanitize the Body

When the calling skill asks for strict mode, the strict-mode rule below replaces the strip and the prompt: find the references, but do not change the body.

Strip references to ephemeral local paths that don't exist on the remote tracker:

- `.claude-work/` paths (scratchpads, notes, questions, commit-msgs, breadcrumbs)

When you strip a reference, print it as `- <path> (line N)` under a `Stripped ephemeral references:` heading. This step deletes text the user wrote. The user must see what you removed. When you strip nothing, print nothing.

Then find the local-only file references that remain. A tracker reader cannot open a file that lives only on the author's disk. A path in the body is local-only when it exists on disk (check with Glob) and one of these is true:

- it is absolute
- it starts with `~`
- the current repository does not track it: `git ls-files --error-unmatch "<path>"` exits non-zero

A repo-relative path that the repository tracks passes, because a reader can open it in the repository. A path that does not exist on disk is not a file reference, so leave it as it is.

**Strict mode.** A calling skill puts the reader in strict mode when the draft is approved text, such as a draft that passed an expected-hash check. In strict mode the reader changes nothing in the body. When the body holds a `.claude-work/` reference or a local-only reference, STOP and print each path with its line under this message:

```text
The filed text would differ from the approved text. Fix these references in the draft, then review the draft again:
```

Outside strict mode, for each local-only reference, ask the user with `AskUserQuestion` and give three options: inline the file content as a fenced code block in place of the reference, remove the reference, or keep it. When you inline or remove a reference, print it as `- <path> (line N): inlined` or `- <path> (line N): removed` under a `Changed local file references:` heading. When you change nothing, print nothing.

Formatting: see `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.
