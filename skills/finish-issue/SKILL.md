---
name: finish-issue
version: 2026.06.17@7173d6a
description: Wrap up issue or side-quest work on the current issues/* or side-quest/* branch. Runs verification, checks documentation needs, and generates a PR description
argument-hint: [optional: issue-number-or-url]
allowed-tools: Read, Write, Glob, Grep, AskUserQuestion, Bash(git branch --show-current), Bash(git status), Bash(git log *), Bash(git diff *), Bash(make lint-fix *), Bash(make test *), Bash(*/skills/auto-number/auto-number.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Finish Issue

Wraps up work on either an `issues/*` or `side-quest/*` branch. Runs verification, checks documentation needs, and generates a PR description (as a working document) via `/note`.

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

## Step 1b: Resolve Active Plan

Read the active-plan pointer written by `/start-issue` or `/start-side-quest` to locate the primary working document:

- **Issue mode:** read `.claude-work/issues/<ID>/active-plan`
- **Side-quest mode:** read `.claude-work/active-plan-<slug>`

The pointer contents is a single project-root-relative path. Record it as the **resolved plan path**. This is the single source of truth for the primary plan.

**If the pointer is missing:** proceed without a resolved plan. Step 4 context gathering falls back to git log and breadcrumbs only.

## Step 2: Pre-PR Verification

Run the project's standard verification commands from the project root:

1. **Working document step check**: scan the resolved plan (note or scratchpad) for unfinished steps before running anything else
2. **Format**: run the project's formatter (fix mode)
3. **Tests**: run the full test suite; all must pass
4. **Check status**: `git status` for uncommitted changes

**Check 1. Working document step check:** Read the resolved plan path (from Step 1b). If it points to a file containing a fenced JSON step block, collect all steps where `"status"` is `"pending"` or `"in_progress"`. If the resolved plan is a note (no JSON step block) or no plan was resolved, proceed silently. There is nothing structured to check.

If any unfinished steps are found, print a warning:

```text
Warning: unfinished steps found in working document:
  - S003 "Add integration tests" (pending)
  - S004 "Update CHANGELOG" (in_progress)
```

Then use `AskUserQuestion` with two options:

- **Proceed anyway**: continue to format, tests, and PR description generation
- **Stop: I'll finish the steps first**. halt and print: "Stopping. Finish the outstanding steps, then re-run `/finish-issue`."

```bash
git status
```

**Checks 2–4 outcomes:**

- If formatting makes changes → prepare a commit
- If tests fail → investigate and fix before proceeding
- If uncommitted changes exist → notify user
- **Check for project-local hooks**: if the project has a `/finish-issue-hook` skill (foundation skill at `.claude/skills/finish-issue-hook/SKILL.md`), it is loaded as additional context automatically. Read it and incorporate whatever it specifies. If no such skill exists, continue with the vanilla workflow. See `/skill-hooks` for the full extension mechanism.

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

- Commit history: read `Base branch:` from the resolved plan (recorded by `/start-issue` or `/start-side-quest`); fall back to `origin/main` if absent. Run: `git log --oneline <base-branch>..HEAD`
- **Actual change set**: run `git diff --stat <base-branch>..HEAD` and `git diff <base-branch>..HEAD`. This is the single source of truth for what actually changed on the branch. Use it to filter which context is relevant — if a file or change doesn't appear in the diff, don't mention it in the PR description
- **Resolved plan** (from Step 1b): read to extract the goal and rationale. This is the primary reference
- Breadcrumbs (if exists): incorporate highlights into the PR description; use the paths below based on mode
- Auxiliary working documents: PR-comment responses, interim analysis notes. Globbed separately so multi-round PR feedback isn't lost. Use the paths below based on mode

**PR template detection:** Check the following locations in order and read the first file found:

1. `.github/pull_request_template.md`
2. `pull_request_template.md`
3. `docs/pull_request_template.md`

Note whether a template was found and its path. This is used in Step 5. If none of these files exist, proceed without a template. The `.github/PULL_REQUEST_TEMPLATE/` directory (multiple templates) is out of scope.

**Issue mode (path differences):**

- Breadcrumbs: `.claude-work/issues/<ID>/breadcrumb.md`
- Auxiliary notes: `Glob(pattern="**/*", path=".claude-work/issues/<ID>/notes")` (excluding the resolved plan if it's a note)
- Auxiliary scratchpads: `Glob(pattern="**/*", path=".claude-work/issues/<ID>/scratchpads")` (excluding the resolved plan if it's a scratchpad)

**Side-quest mode (path differences):**

- Breadcrumbs: `.claude-work/breadcrumb-<slug>.md`
- Auxiliary notes: `Glob(pattern="*side-quest-<slug>*", path=".claude-work/notes")` (excluding the resolved plan)
- Auxiliary scratchpads: `Glob(pattern="*side-quest-<slug>*", path=".claude-work/scratchpads")` (excluding the resolved plan)

## Step 5: Generate PR Description Working Document

See `/pre-write` for the think-before-writing rule: complete all reasoning before writing the first word.

**Issue mode**: use description: `finish-issue-<ID>`

**Side-quest mode**: use description: `finish-<slug>` (flat placement since side-quest branches don't match `issues/*`)

**If a PR template was detected in Step 4:** use it as the structural base. Preserve its section headers and checkbox structure verbatim. Only replace placeholder content with the actual information gathered (summary, changes, test plan, etc.). In issue mode, add a `Closes https://github.com/{owner}/{repo}/issues/{NUMBER}` line at the end if the template doesn't already include one. In side-quest mode, omit the Closes line.

**If no PR template was found:** use the built-in template below.

```markdown
[<branch-name>] Title

## Summary

2-3 sentences on what this accomplishes.

## Changes

Each bullet describes a capability or behaviour change, never a file. Files can appear inline as context (`via skills/finish-issue/SKILL.md`) but the bullet subject is always what changed for the user or the system. Group by theme, not by path.

Bad (file-inventory — what this skill should never produce):
- `skills/finish-issue/SKILL.md` — updated Changes section template
- `skills/README.md` — updated finish-issue description

Good (capability-grouped):
- PR description Changes section now requires capability-focused bullets with a concrete rule and before/after example, replacing the soft "group related changes" guidance
- Unused `--scratchpad` opt-in removed from the finish-issue skill
- Documentation: CHANGELOG [added]; README [updated]; omit this line when the changes are either not user-facing or do not need documentation

## Key Discoveries

Populate from breadcrumbs or the active plan's assumptions/deviations. Each bullet is a notable finding, decision, or rationale that shaped the approach. Only include findings that relate to the final shipped changes — skip abandoned approaches and stale breadcrumbs. Omit this entire section (header and all) when there is nothing to surface.

## Test Plan

- [ ] All existing tests pass
- [ ] New tests added for: [list] (omit if none)
- [ ] Manual testing: [describe] (omit if not applicable)

## Related

If issue mode:
- Closes https://github.com/{owner}/{repo}/issues/{NUMBER}

If side-quest mode:
- Orthogonal improvement discovered during active development
- Base branch: <branch this was cut from>
```

**Diff-filtering rule:** The `## Changes` section must be derivable from the `git diff --stat` output captured in Step 4 — one bullet per logical grouping in the diff, not one bullet per conversation turn. Drop any mention of files, edits, or approaches that don't appear in the final diff. The `## Summary` must describe what shipped, not what was considered. Populate `## Key Discoveries` from breadcrumbs or the active plan's assumptions/deviations. Only include findings that relate to the final shipped changes. If an approach was tried then replaced, only the final approach matters. Omit the section entirely when there is nothing to surface.

Formatting: see `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.

### Output Anchors

Deliverable: a single text file whose first line is the PR title and whose remaining lines are the PR description body. Both are consumed downstream: `gh pr create --title "<first line>" --body-file <path>` reads them from one file.
Length: title under 70 characters, formatted `[<branch-name>] Short summary`. Body: 2 to 3 sentences in Summary; 3 to 8 bullets in Changes; 2 to 5 checkboxes in Test Plan. Whole document fits on one screen unless the branch is unusually large.
Format: line 1 is the title. Line 2 is blank. The remaining lines are the body, following the PR template sections in order (Summary, Changes, Key Discoveries, Test Plan, Related). If a repository template was detected in Step 4, follow that template's body structure instead and preserve its headers verbatim. The title-on-line-1 convention is independent of the template.
Scope: changes that shipped on this branch only. Document future work, alternatives considered, and abandoned approaches elsewhere.
Tone: direct, why-focused, reviewer-facing. Avoid restating the diff.

Before writing the PR description, skim the text for AI-writing tells: em dashes, filler phrases (in order to, due to the fact that), vague attributions, generic positive conclusions. Rewrite any you find.

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

Files created:
- <actual-path-to-pr-description> (PR description)

---

Ready for PR. Review the file and:
1. Commit: git add -p && git commit -F <actual-path-to-pr-description>
2. Push and create PR: gh pr create --title "..." --body-file <actual-path-to-pr-description>
3. Or ask Claude to create the PR
```

**Side-quest mode:**

```text
=== Side-Quest '<slug>' Ready for PR ===

Verification:
- format: [ran / no changes needed]
- tests: [all pass / X tests, Y passing]
- uncommitted changes: [none / list]

Files created:
- <actual-path-to-pr-description> (PR description)

---

Ready for PR. Review the file and:
1. Commit: git add -p && git commit -F <actual-path-to-pr-description>
2. Push and create PR: gh pr create --title "..." --body-file <actual-path-to-pr-description>
3. Or ask Claude to create the PR
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
- [ ] Active-plan pointer resolved (or missing. Step 4 degrades to git log + breadcrumbs)
- [ ] No pending/in-progress steps in the resolved plan (or user confirmed to proceed). Check skipped silently if the resolved plan is a note
- [ ] PR description doesn't reference ephemeral files
- [ ] Documentation needs have been assessed
- [ ] Working document created with PR description
