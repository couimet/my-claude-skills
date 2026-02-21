---
name: create-github-issue
description: Create a GitHub issue from a file draft or inline description — with smart label discovery and sub-issue linking
argument-hint: <file-path-or-title>
allowed-tools: Read, Glob, Bash(gh label list *), Bash(gh issue create *), Bash(gh api graphql *)
---

# Create GitHub Issue

Create a GitHub issue with smart label discovery and optional sub-issue linking. Reads from any file (scratchpad, markdown, extensionless — including drag-dropped paths) or accepts an inline title.

**Input:** $ARGUMENTS (a file path, or a title for interactive creation)

## Step 1: Parse Input

Determine the input mode from `$ARGUMENTS`:

- **File path** — if the argument points to an existing file (any path, any extension or none), treat it as a draft to extract from. This covers `.scratchpads/*.txt`, markdown files, extensionless files, and drag-dropped paths from the terminal.
- **Inline title** — otherwise, treat the entire argument as the issue title for interactive creation.

## Step 2: Extract Issue Content

### From File

Read the file and extract:

- **Title** — the first `#`-level heading (strip the `#` prefix)
- **Body** — everything after the title heading

If the file contains a `## Parent` or `Parent: #NN` line, extract the parent issue number for sub-issue linking in Step 7.

### From Inline Title

Use the argument as the title. Prompt the user to provide a body — either inline or by pointing to an existing file.

## Step 3: Sanitize Body

Strip references to ephemeral local paths that don't exist on GitHub:

- `.scratchpads/` paths
- `.claude-questions/` paths
- `.commit-msgs/` paths
- `.breadcrumbs/` paths

**Print the list of stripped references** so the user can verify nothing important was removed. Format as:

```text
Stripped ephemeral references:
- .scratchpads/issues/42/0001-plan.txt (line 12)
- .claude-questions/issues/42/0001-scope.txt (line 28)
```

If no ephemeral references were found, print:

```text
No ephemeral references found — body is clean.
```

## Step 4: Discover Repo Labels

Fetch all labels from the current repository:

```bash
gh label list --json name,description --limit 200
```

Classify labels into two groups:

**GitHub defaults** — these ship with every new repo and don't indicate structured label usage:

- bug, documentation, duplicate, enhancement, good first issue, help wanted, invalid, question, wontfix

**Structured labels** — anything beyond the defaults. Their presence indicates the repo uses intentional label conventions (e.g., `type:bug`, `priority:high`, `area:checkout`).

## Step 5: Prompt for Labels

### If only default labels exist

Ask the user which labels to apply (simple multi-select from the defaults). The user can also choose "none".

### If structured labels are detected

Tell the user the repo uses structured labels and present them grouped by prefix (e.g., all `type:*` together, all `priority:*` together). Ask the user to select appropriate labels.

Example prompt:

```text
This repo uses structured labels beyond GitHub defaults:

  type: bug, enhancement, feature, refactor
  priority: high, medium, low
  area: checkout, admin, api

  Other: good first issue, help wanted

Which labels should this issue have?
```

Use `/question` if the label choice requires extended discussion. Otherwise, use inline prompting.

## Step 6: Create the Issue

```bash
gh issue create --title "<TITLE>" --label "<LABEL1>,<LABEL2>" --body-file - <<'EOF'
<SANITIZED_BODY>
EOF
```

Omit the `--label` flag entirely when no labels are selected. Capture the returned issue URL.

## Step 7: Link as Sub-Issue (If Parent Specified)

If a parent issue number was extracted in Step 2, link the new issue as a sub-issue using the GitHub GraphQL API.

Parse `OWNER` and `REPO` from the issue URL returned in Step 6 (`https://github.com/{OWNER}/{REPO}/issues/{NUMBER}`).

First, get the node IDs:

```bash
gh api graphql -H 'GraphQL-Features: sub_issues' -f query='
  query($owner: String!, $repo: String!, $parent: Int!, $child: Int!) {
    repository(owner: $owner, name: $repo) {
      parent: issue(number: $parent) { id }
      child: issue(number: $child) { id }
    }
  }
' -f owner=OWNER -f repo=REPO -F parent=PARENT_NUMBER -F child=CHILD_NUMBER
```

Then link them:

```bash
gh api graphql -H 'GraphQL-Features: sub_issues' -f query='
  mutation($parentId: ID!, $childId: ID!) {
    addSubIssue(input: {issueId: $parentId, subIssueId: $childId}) {
      issue { number title }
      subIssue { number title }
    }
  }
' -f parentId=PARENT_NODE_ID -f childId=CHILD_NODE_ID
```

If either `gh api graphql` call returns an error (e.g., `"NOT_FOUND"`, `"FORBIDDEN"`, or an unknown field/mutation), skip sub-issue linking and note the failure in the Step 8 report as:

```text
Sub-issue linking: failed (<error summary>) — link manually if needed.
```

If no parent was specified, skip this step.

## Step 8: Report

Print a summary:

```text
Created: <ISSUE_URL>
Title: <TITLE>
Labels: <LABEL1>, <LABEL2>
Parent: #<PARENT_NUMBER> (linked as sub-issue)  ← only if applicable
```

Format all code references per the `/code-ref` skill conventions.

Format all prose output per the `/prose-style` skill conventions.
