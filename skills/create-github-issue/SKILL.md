---
name: create-github-issue
version: 2026.03.16.1@4c23535
description: Create a GitHub issue from a file draft or inline description — with smart label discovery and sub-issue linking
argument-hint: <file-path-or-title>
allowed-tools: Read, Write, Glob, Bash(gh repo view *), Bash(gh label list *), Bash(gh issue create *), Bash(*/skills/create-github-issue/link-sub-issue.sh *), Bash(*/skills/auto-number/auto-number.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Create GitHub Issue

Create a GitHub issue with smart label discovery and optional sub-issue linking. Reads from any file (scratchpad, markdown, extensionless — including drag-dropped paths) or accepts an inline title.

**Input:** $ARGUMENTS (a file path, or a title for interactive creation)

## Step 1: Parse Input

Determine the input mode from `$ARGUMENTS`:

- **File path** — if the argument points to an existing file (any path, any extension or none), treat it as a draft to extract from. This covers `.claude-work/scratchpads/*.txt`, markdown files, extensionless files, and drag-dropped paths from the terminal.
- **Inline title** — otherwise, treat the entire argument as the issue title for interactive creation.

## Step 2: Extract Issue Content

### From File

Read the file and extract:

- **Title** — the first `#`-level heading (strip the `#` prefix)
- **Body** — everything after the title heading

If the file contains a `## Parent` or `Parent: #NN` line, extract the parent issue number for sub-issue linking in Step 7.

If the file contains a `**Target repo:** owner/repo` line (e.g., `**Target repo:** couimet/my-claude-skills`), extract it as the target repository override. When no target repo line is present, infer owner/repo from the current git remote (`gh repo view --json owner,name`).

### From Inline Title

Use the argument as the title. Prompt the user to provide a body — either inline or by pointing to an existing file.

## Step 3: Sanitize Body

Strip references to ephemeral local paths that don't exist on GitHub:

- `.claude-work/` paths (scratchpads, questions, commit-msgs, breadcrumbs)

**Print the list of stripped references** so the user can verify nothing important was removed. Format as:

```text
Stripped ephemeral references:
- .claude-work/issues/42/scratchpads/0001-plan.txt (line 12)
- .claude-work/issues/42/questions/0001-scope.txt (line 28)
```

If no ephemeral references were found, print:

```text
No ephemeral references found — body is clean.
```

## Step 4: Discover Labels and Prompt for Selection

Follow `/label-discovery` to fetch labels, classify them, and prompt the user. Pass `--repo owner/repo` when a target repo override was extracted in Step 2.

## Step 5: Create the Issue

Use the Write tool to save the sanitized body to an auto-numbered file in the issue's scratchpads folder via `/scratchpad` (e.g., `.claude-work/issues/<ID>/scratchpads/NNNN-issue-body.txt`). This keeps the body traceable alongside other working files and avoids heredoc compound commands that don't match `allowed-tools` globs.

Then create the issue with a simple one-liner (pass `--repo owner/repo` when a target repo override was extracted in Step 2; omit it to use the current git remote):

```bash
gh issue create --title "<TITLE>" --label "<LABEL1>,<LABEL2>" --body-file <BODY_FILE_PATH>
gh issue create --repo owner/repo --title "<TITLE>" --label "<LABEL1>,<LABEL2>" --body-file <BODY_FILE_PATH>
```

Omit the `--label` flag entirely when no labels are selected. Capture the returned issue URL.

## Step 6: Link as Sub-Issue (If Parent Specified)

If a parent issue number was extracted in Step 2, link the new issue as a sub-issue using the `link-sub-issue.sh` script.

Parse `OWNER`, `REPO`, and `CHILD_NUMBER` from the issue URL returned in Step 5 (`https://github.com/{OWNER}/{REPO}/issues/{CHILD_NUMBER}`). If a target repo override was extracted in Step 2, use that owner/repo instead.

Run the script once per child issue to link:

```bash
skills/create-github-issue/link-sub-issue.sh --owner "$OWNER" --repo "$REPO" --parent "$PARENT_NUMBER" --child "$CHILD_NUMBER"
```

The script handles all GraphQL calls internally, using `jq -n` to build payloads via temp files to avoid zsh history expansion stripping `!` from GraphQL type annotations (`String!`, `Int!`, `ID!`). It prints `linked #<child> → #<parent>` on success or an error message on failure (exit 1).

If the script fails, note it in the Step 7 report as:

```text
Sub-issue linking: failed (<error summary>) — link manually if needed.
```

If no parent was specified, skip this step.

## Step 7: Report

Print a summary:

```text
Created: <ISSUE_URL>
Title: <TITLE>
Labels: <LABEL1>, <LABEL2>
Parent: https://github.com/{OWNER}/{REPO}/issues/{PARENT_NUMBER} (linked as sub-issue)  ← only if parent specified AND linking succeeded
Sub-issue linking: failed (<error summary>) — link manually if needed.  ← only if parent specified AND linking failed
```

Code refs: path/to/file.ts#L10-L20 (workspace-relative, no backticks wrapping the ref).

Never hard-wrap prose output — each paragraph is one continuous line; line breaks for structure only.

GitHub refs: full URLs only — `https://github.com/{owner}/{repo}/issues/{N}` or `https://github.com/{owner}/{repo}/pull/{N}`, never `#NNN`.
