---
name: label-discovery
version: 2026.03.16.3@fecab09
user-invocable: false
description: Fetches GitHub labels, classifies them as defaults vs structured, and prompts the user for selection. Auto-consulted by /create-github-issue.
allowed-tools: Bash(gh label list *)
---

# Label Discovery

Fetch labels from a GitHub repository, classify them, and prompt the user for selection.

## Fetch Labels

Fetch all labels from the target repository. If the calling skill provides a `--repo owner/repo` override, pass it through:

```bash
gh label list --json name,description --limit 200
gh label list --repo owner/repo --json name,description --limit 200
```

## Classify Labels

Classify into two groups:

**GitHub defaults** — ship with every new repo, don't indicate structured usage:

- bug, documentation, duplicate, enhancement, good first issue, help wanted, invalid, question, wontfix

**Structured labels** — anything beyond the defaults. Their presence indicates intentional label conventions (e.g., `type:bug`, `priority:high`, `area:checkout`).

## Prompt for Selection

### If only default labels exist

Ask the user which labels to apply (simple multi-select from the defaults). The user can also choose "none".

### If structured labels are detected

Present them grouped by prefix (e.g., all `type:*` together, all `priority:*` together). Ask the user to select appropriate labels.

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
