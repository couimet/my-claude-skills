---
name: finish-issue
description: Wrap up issue work - run verification, check documentation needs, generate PR description
argument-hint: [optional: issue-number-or-url]
allowed-tools: Read, Write, Glob, Grep, Bash(git branch --show-current), Bash(git status), Bash(git log *), Bash(git diff *)
---

# Finish Issue

Symmetrical companion to `/start-issue` — handles the "wrap up" phase of issue work.

**Input:** $ARGUMENTS

If no argument provided, extract issue number from current branch name using `/issue-context` rules.

## Step 1: Determine Issue Number

```bash
git branch --show-current
```

Parse the issue number from `issues/<NUMBER>` pattern (per `/issue-context`) or use the provided argument.

## Step 2: Pre-PR Verification

Run the project's standard verification commands from the project root:

1. **Format** — run the project's formatter (fix mode)
2. **Tests** — run the full test suite; all must pass
3. **Check status** — `git status` for uncommitted changes

```bash
git status
```

- If formatting makes changes → prepare a commit
- If tests fail → investigate and fix before proceeding
- If uncommitted changes exist → notify user

## Step 3: Documentation Review

Check if documentation updates are needed. Common touchpoints:

**CHANGELOG**:

- User-facing changes → Add entry (Added/Changed/Fixed)
- Internal refactoring/infrastructure → No entry (users don't see it)

**README**:

- New command → Document with keybinding
- New setting → Document in Configuration
- New feature → Document appropriately
- Internal changes → Usually no update

**Unreleased markers** (if project uses trunk-based documentation):

- New section headers → Add `<sup>Unreleased</sup>` marker
- New command/setting table rows → Add `<sup>Unreleased</sup>` marker
- If no top-of-README banner exists → Add one explaining the convention
- Check project's CLAUDE.md or release docs for the exact convention

**Project-specific integration points**:

- Verify commands/keybindings/settings/menus already added during implementation

## Step 4: Gather Context for PR Description

Collect information from:

- Breadcrumbs file (if exists): `.breadcrumbs/<identifier>.md` (where `<identifier>` is the issue number or side-quest slug per `/issue-context`)
- Scratchpads matching the work: use Glob to find `*<identifier>*` in `.scratchpads/`
- Commit history: `git log --oneline origin/main..HEAD`
- Commit details: `git log origin/main..HEAD`

**Breadcrumbs** capture key discoveries and decisions made during implementation. If present, incorporate highlights into the PR description.

## Step 5: Generate PR Description Scratchpad

Use `/scratchpad` to create a working document. The `/issue-context` skill will handle directory placement based on the branch.

Use description: `finish-issue-<identifier>`

The PR description MUST follow this template:

```markdown
[issues/NUMBER] Title

## Summary

2-3 sentences on what this accomplishes.

## Changes

- Bulleted list of key changes
- Omit file lists (PR shows modified files)
- Group related changes

## Key Discoveries (if breadcrumbs exist)

- [Notable finding that shaped the approach]
- [Key decision made and rationale]
- (Omit this section if no breadcrumbs)

## Test Plan

- [ ] All existing tests pass
- [ ] New tests added for: [list]
- [ ] Manual testing: [describe if applicable]

## Documentation

- [ ] CHANGELOG: [entry added / not needed - reason]
- [ ] README: [updated / not needed - reason]

## Related

- Closes #NUMBER
```

Format all code references per the `/code-ref` skill conventions.

### PR Description Rules

- **NEVER** reference `.scratchpads/`, `.claude-questions/`, or `.breadcrumbs/` files
- These are local/ephemeral and inaccessible from GitHub
- Capture all relevant information directly in the PR body

## Step 6: Handle Ambiguity

If unclear whether documentation is needed or other decisions arise:

- Use `/question` to create a questions file and gather user input
- Do NOT guess on user-facing decisions

## Step 7: Report Status and STOP

Print a summary:

```text
=== Issue #NUMBER Ready for PR ===

Verification:
- format: [ran / no changes needed]
- tests: [all pass / X tests, Y passing]
- uncommitted changes: [none / list]

Documentation:
- CHANGELOG: [entry added / not needed - reason]
- README: [updated / not needed - reason]

Files created:
- .scratchpads/NNNN-finish-issue-NUMBER.txt (PR description)

---

Ready for PR. Review the scratchpad and:
1. Create PR: gh pr create --title "..." --body-file .scratchpads/NNNN-finish-issue-NUMBER.txt
2. Or ask Claude to create the PR
```

**IMPORTANT: Do NOT create the PR automatically.**

This skill prepares everything for the PR. Wait for the user to:

- Review the PR description
- Explicitly ask to create the PR (e.g., "create PR", "submit")

## Quality Checklist

Before finishing, verify:

- [ ] Project's formatter ran successfully
- [ ] Project's test suite passes
- [ ] No uncommitted changes (or user has been notified)
- [ ] PR description doesn't reference ephemeral files
- [ ] Documentation needs to be assessed
- [ ] Scratchpad created with PR description
