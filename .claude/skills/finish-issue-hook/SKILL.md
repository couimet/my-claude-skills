---
name: finish-issue-hook
version: 2026.07.14@local
description: Proect-specific for /finish-issue
user-invocable: false
allowed-tools: AskUserQuestion, Bash(git diff *), Bash(grep *), Bash(scripts/check-transitive-tools.sh *)
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

## Transitive Permission Diff Check

If any `skills/*/SKILL.md` file changed on this branch, check for newly introduced transitive permission gaps by running from the project root:

```bash
scripts/check-transitive-tools.sh --diff <base-branch>..HEAD
```

Where `<base-branch>` is read from the resolved plan `Base branch:` field (fallback `origin/main`, the same fallback the CHANGELOG checks above use).

If the script exits 0, proceed silently. If it exits 1, the reported gaps are likely invocations; confirm each reference before adding the permission. For each gap, add the missing permission to the caller `allowed-tools` front matter, then re-run the script until it exits 0 and re-run `make test`. Note the fixes in Step 7 verification report. Do not halt the workflow.
