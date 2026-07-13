---
name: rebase-issue
version: 2026.07.10@aa48370
description: Rebase the current issue branch onto origin/main (or a specified target) after upstream PRs merge. Handles conflict resolution, squashes to a single commit, and runs autonomously
argument-hint: <target>
user-invocable: true
allowed-tools: Read, Write, AskUserQuestion, Bash(git branch --show-current), Bash(git fetch *), Bash(git log *), Bash(git diff *), Bash(git rebase *), Bash(git reset *), Bash(git commit *), Bash(git add *), Bash(git checkout *), Bash(git merge-base *), Bash(git rev-parse *), Bash(git status *), Bash(*/skills/issue-context/claude-work-root.sh *), Bash(*/skills/rebase-issue/resolve-commit-msg.sh *)
---

# Rebase Issue

Rebase the current issue branch onto origin/main (or a specified target) after upstream PRs merge. Handles conflict resolution, squashes to a single commit, and runs autonomously.

**Input:** $ARGUMENTS

If no argument provided, defaults to `origin/main`.

## Step 1: Validate Branch

```bash
git branch --show-current
```

The branch must match `issues/<NUMBER>`. If it does not, STOP:

```text
Not on an issue branch. `/rebase-issue` requires an `issues/*` branch.
Current branch: <branch>
```

## Step 2: Fetch Latest

```bash
git fetch origin
```

## Step 3: Resolve Target

If `$ARGUMENTS` was provided, use it as the target ref. Otherwise default to `origin/main`. Accept any valid git ref: `origin/main`, `main`, another issue branch (for stacked PRs), and so on.

## Step 4: Show Divergence — Our Commits

```bash
git log --oneline <target>..HEAD
```

Shows commits on our branch that are not on the target. If empty, there is nothing to rebase. Report "No upstream changes — nothing to rebase" and stop the procedure here.

## Step 5: Show Divergence — Target Commits

```bash
git log --oneline HEAD..<target>
```

Shows commits on the target that are not on our branch. This is what will be replayed onto our branch.

## Step 6: Assess Conflict Potential

Run both commands:

```bash
git diff --name-only $(git merge-base <target> HEAD)..HEAD
```

```bash
git log --name-only HEAD..<target>
```

Compare the file lists. Files appearing in both lists are potential conflict areas. Report these to the user before proceeding so they know what to expect.

## Step 7: Rebase

```bash
git rebase <target>
```

## Step 8: Handle Conflicts (If Any)

If `git rebase` reports conflicts, resolve them following this strategy:

- **Infrastructure/refactors from upstream win.** If upstream restructured code, take their version with `git checkout --ours <file>` (during rebase, `--ours` refers to the target branch).
- **Our issue-specific logic is ported onto the new infrastructure.** After taking the upstream version, manually re-apply our change.
- **Test expectations must match current behavior.** If upstream changed output formats or APIs, update our test expectations accordingly.
- After resolving each file: `git add <file>` then `git rebase --continue`.
- **Unresolvable conflicts:** if a conflict cannot be resolved with this strategy, abort with `git rebase --abort` and ask the user for guidance.

## Step 9: Verify

After rebase completes (cleanly or after conflict resolution):

```bash
git diff <target> --stat
```

Verify only issue-specific changes remain. Then run the project's formatter and test suite (project-agnostic — the harness will prompt for the specific commands). If tests fail, investigate and fix before proceeding.

## Step 10: Squash

```bash
git reset --soft <target>
```

All changes are now staged as a single diff, ready for one commit.

## Step 11: Read Commit Message

Run the commit message resolution script, which tries three sources in order:

1. **`last-finish-issue` pointer** — reads the PR description path from `<base>/issues/<NUMBER>/last-finish-issue` and returns its contents
2. **Find PR description in notes/** — searches for the most recent `*finish-issue-<NUMBER>*` file in `<base>/issues/<NUMBER>/notes/`
3. **git log fallback** — captures `git log --format=%B <target>..HEAD` (the original commits before the soft reset)

```bash
~/.claude/skills/rebase-issue/resolve-commit-msg.sh <target> <NUMBER>
```

The script outputs the commit message to stdout on success (exit 0) or an error to stderr (exit 1) if all sources are empty.

## Step 12: Commit

If the script succeeded, write its stdout to a temporary file and commit:

```bash
git commit -F <commit-message-file>
```

If the script failed (exit 1), all sources are empty. Abort and ask the user for a commit message.

## Step 13: Report and Offer Push

Report: branch now has 1 commit on top of `<target>`. Show `git log --oneline -1` and `git diff <target> --stat`.

First, use `AskUserQuestion` to confirm the target remote and branch (default to the configured upstream remote and current branch name; if no upstream is configured, default to `origin` and the current branch name). Then use `AskUserQuestion` to ask whether to push:

- **Yes, push with --force-with-lease**: run `git push --force-with-lease <confirmed-remote> <confirmed-branch>` (harness will prompt for permission since push is not auto-allowed)
- **No, I'll push manually**: report that the branch is ready for manual push

## Conflict Resolution Strategy

When `git rebase` encounters conflicts during Step 8, apply this strategy:

- **Infrastructure/refactors from upstream win.** If upstream restructured code, take their version with `git checkout --ours <file>` (during rebase, `--ours` refers to the target branch).
- **Our issue-specific logic is ported onto the new infrastructure.** After taking the upstream version, manually re-apply our change.
- **Test expectations must match current behavior.** If upstream changed output formats or APIs, update our test expectations accordingly.
- After resolving each file: `git add <file>` then `git rebase --continue`.
- **Unresolvable conflicts:** if a conflict cannot be resolved with this strategy, abort with `git rebase --abort` and ask the user for guidance.

## Edge Cases

- **No upstream changes:** `HEAD..<target>` is empty. Nothing to rebase -- report and exit at Step 4.
- **Stacked PRs:** when `<target>` is another issue branch, the workflow is identical; the AskUserQuestion in Step 13 should confirm the correct remote branch.
- **Clean rebase:** `git rebase <target>` completes with no conflicts. Proceed directly to Step 9.
- **Unresolvable conflicts:** abort with `git rebase --abort` and ask the user.
- **Missing pointer file:** fall back to find, then to git log (Step 11).
- **Tests fail after rebase:** investigate and fix before proceeding; check if project prerequisites need updating first.
- **Many commits on branch:** still squash to 1; the finish-issue PR description is the authoritative message.

## Interaction with Other Skills

- `/finish-issue` generates the PR description and writes the `last-finish-issue` pointer file. Run `/rebase-issue` AFTER a PR has been reviewed and upstream PRs have been merged.
- `/commit-msg` generates per-commit message files; those commits get squashed into the single commit.
- The rebase skill produces output suitable for `git push --force-with-lease` to update the existing PR.

## Quality Checklist

Before finishing, verify:

- [ ] Branch is an `issues/*` branch (Step 1)
- [ ] Target resolved correctly (from argument or defaulted to `origin/main`)
- [ ] Conflicts handled with the defined strategy (upstream infrastructure wins; our logic ported on top)
- [ ] Rebase completed cleanly (or conflicts resolved)
- [ ] Project formatter ran successfully
- [ ] Project test suite passes
- [ ] Changes squashed to a single commit on top of `<target>`
- [ ] Commit message sourced from pointer file, PR description, or git log fallback
- [ ] Push confirmed with the user before executing
