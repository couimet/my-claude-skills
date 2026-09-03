---
name: label-discovery
version: 2026.09.02@026b73f
user-invocable: false
description: 'Fetches GitHub labels, classifies them as defaults vs structured, and prints them grouped by prefix for the user to apply. Auto-consulted by /create-github-issue.'
allowed-tools: Bash(gh label list *)
---

# Label Discovery

Fetch labels from a GitHub repository, classify them, and print the groups so the user can apply them on the issue page. The skill stops at printing. It does not select labels and it never prompts for a choice.

## Fetch Labels

Fetch all labels from the target repository. If the calling skill provides a `--repo owner/repo` override, pass it through:

```bash
gh label list --json name,description --limit 200
gh label list --repo owner/repo --json name,description --limit 200
```

## Classify Labels

Classify into two groups:

**GitHub defaults**: ship with every new repo, don't indicate structured usage:

- bug, documentation, duplicate, enhancement, good first issue, help wanted, invalid, question, wontfix

**Structured labels**: anything beyond the defaults. Their presence indicates intentional label conventions (e.g., `type:bug`, `priority:high`, `area:checkout`).

## Print the Groups

### If only default labels exist

Print that the repo uses only GitHub default labels and list them.

### If structured labels are detected

Print them grouped by prefix (all `type:*` together, all `priority:*` together, all `area:*` together) with the remaining defaults under an Other heading:

```text
This repo uses structured labels beyond GitHub defaults:

  type: bug, enhancement, feature, refactor
  priority: high, medium, low
  area: checkout, admin, api

  Other: good first issue, help wanted
```

Then stop. The calling skill shows the issue URL alongside these groups and invites the user to apply labels on the issue page, where GitHub's own autocomplete selects them.

Formatting: see `/prose-style` for hard-wrap and GitHub-reference rules.
