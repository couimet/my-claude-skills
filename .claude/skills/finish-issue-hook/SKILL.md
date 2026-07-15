---
name: finish-issue-hook
version: 2026.07.14@local
description: Proect-specific for /finish-issue
user-invocable: false
allowed-tools: Bash(git diff *), Bash(grep *)
---

# Finish-Issue Hook (my-claude-skills)

Consulted automatically by /finish-issue during Step 2 (Pre-PR Verification). Adds CHANGELOG-specific checks to the standard verification workflow.

## CHANGELOG Modification Check

Check whether CHANGELOG.md was modified on this branch:

```bash
git diff --name-only <base-branch>..HEAD -- CHANGELOG.md
```

If no diff, print a non-blocking reminder that user-facing changes need a CHANGELOG entry. Do not halt.

## CHANGELOG Ordering Check

If CHANGELOG.md was modified, verify version headings are in descending order (newest first) per the rule in CLAUDE.md CHANGELOG Conventions:

```bash
grep '^## [0-9]' CHANGELOG.md
```

If out of order, warn and offer fix-or-proceed via `AskUserQuestion`. If correctly ordered, proceed silently.
