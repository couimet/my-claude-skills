---
name: finish-issue
version: 2026.03.04@827b5e7
description: Wrap up issue or side-quest work - run verification, check documentation needs, generate PR description
argument-hint: [optional: issue-number-or-url]
allowed-tools: Read, Write, Glob, Grep, AskUserQuestion, Bash(git branch --show-current), Bash(git status), Bash(git log *), Bash(git diff *)
---

# Finish Issue

Wraps up work on either an `issues/*` or `side-quest/*` branch — runs verification, checks documentation needs, and generates a PR description scratchpad.

**Input:** $ARGUMENTS

If no argument provided, detect context from the current branch name.

## Step 1: Determine Branch Mode

```bash
git branch --show-current
```

Parse the branch name to set **mode** and **identifier**:

| Branch pattern | Mode | Identifier |
| --- | --- | --- |
| `issues/<NUMBER>` | `issue` | The issue number (e.g., `42`) |
| `side-quest/<slug>` | `side-quest` | The full slug (e.g., `cleanup-test-mocks`) |

If an argument was provided and is a number, use it as the issue number (issue mode).

**If the branch matches neither pattern and no argument was provided**, STOP:

```text
Not on a work branch. `/finish-issue` requires an `issues/*` or `side-quest/*` branch.
Current branch: <branch>
```

## Step 2: Pre-PR Verification

Run the project's standard verification commands from the project root:

1. **Scratchpad step check** — scan any scratchpad associated with the current work for unfinished steps before running anything else
2. **Format** — run the project's formatter (fix mode)
3. **Tests** — run the full test suite; all must pass
4. **Check status** — `git status` for uncommitted changes

**Check 1 — Scratchpad step check:** Locate scratchpad files for the current work:

- Issue mode: `Glob(pattern="*.txt", path=".claude-work/issues/<ID>/scratchpads")`
- Side-quest mode: `Glob(pattern="*side-quest-<slug>*.txt", path=".claude-work/scratchpads")`

For each file found, look for a fenced JSON step block. If one is present, collect all steps where `"status"` is `"pending"` or `"in_progress"`. If no scratchpad files exist, or none contain a JSON step block, proceed silently.

If any unfinished steps are found, print a warning:

```text
Warning: unfinished steps found in scratchpad:
  - S003 "Add integration tests" (pending)
  - S004 "Update CHANGELOG" (in_progress)
```

Then use `AskUserQuestion` with two options:

- **Proceed anyway** — continue to format, tests, and PR description generation
- **Stop — I'll finish the steps first** — halt and print: "Stopping. Finish the outstanding steps, then re-run `/finish-issue`."

```bash
git status
```

**Checks 2–4 outcomes:**

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

- Commit history: read `Base branch:` from the scratchpad (recorded by `/start-issue` or `/start-side-quest`); fall back to `origin/main` if absent. Run: `git log --oneline <base-branch>..HEAD`
- Scratchpads — read to extract the goal and rationale; use the paths below based on mode
- Breadcrumbs (if exists) — incorporate highlights into the PR description; use the paths below based on mode

**Issue mode (path differences):**

- Breadcrumbs: `.claude-work/issues/<ID>/breadcrumb.md`
- Scratchpads: `Glob(pattern="**/*", path=".claude-work/issues/<ID>/scratchpads")`

**Side-quest mode (path differences):**

- Breadcrumbs: `.claude-work/breadcrumb-<slug>.md`
- Scratchpads: `Glob(pattern="*side-quest-<slug>*", path=".claude-work/scratchpads")`

## Step 5: Generate PR Description Scratchpad

Use `/scratchpad` to create a working document. The `/issue-context` skill will handle directory placement based on the branch.

**Issue mode** — use description: `finish-issue-<ID>`

**Side-quest mode** — use description: `finish-<slug>` (flat placement since side-quest branches don't match `issues/*`)

The PR description MUST follow this template, adjusted for mode:

**Issue mode:**

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

- Closes https://github.com/{owner}/{repo}/issues/{NUMBER}  ← full URL per /github-ref
```

**Side-quest mode:**

```markdown
[side-quest/<slug>] Title

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

- Orthogonal improvement discovered during active development
- Base branch: <branch this was cut from>
```

Format all code references per the `/code-ref` skill conventions.

Never hard-wrap prose output — each paragraph is one continuous line; line breaks for structure only.

Format all GitHub references per the `/github-ref` skill conventions.

### PR Description Rules

- **NEVER** reference `.claude-work/` files (scratchpads, questions, commit-msgs, breadcrumbs)
- These are local/ephemeral and inaccessible from GitHub
- Capture all relevant information directly in the PR body

## Step 6: Handle Ambiguity

If unclear whether documentation is needed or other decisions arise:

- Use `/question` to create a questions file and gather user input
- Do NOT guess on user-facing decisions

## Step 7: Report Status and STOP

**Issue mode:**

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
- .claude-work/issues/NUMBER/scratchpads/NNNN-finish-issue-NUMBER.txt (PR description)

---

Ready for PR. Review the scratchpad and:
1. Create PR: gh pr create --title "..." --body-file .claude-work/issues/NUMBER/scratchpads/NNNN-finish-issue-NUMBER.txt
2. Or ask Claude to create the PR
```

**Side-quest mode:**

```text
=== Side-Quest '<slug>' Ready for PR ===

Verification:
- format: [ran / no changes needed]
- tests: [all pass / X tests, Y passing]
- uncommitted changes: [none / list]

Documentation:
- CHANGELOG: [entry added / not needed - reason]
- README: [updated / not needed - reason]

Files created:
- .claude-work/scratchpads/NNNN-finish-<slug>.txt (PR description)

---

Ready for PR. Review the scratchpad and:
1. Create PR: gh pr create --title "..." --body-file .claude-work/scratchpads/NNNN-finish-<slug>.txt
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
- [ ] No pending/in-progress steps in scratchpad (or user confirmed to proceed)
- [ ] PR description doesn't reference ephemeral files
- [ ] Documentation needs have been assessed
- [ ] Scratchpad created with PR description
