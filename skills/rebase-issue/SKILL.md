---
name: rebase-issue
version: 2026.07.14.3@8469237
description: Rebase the current issue branch onto origin/main (or a specified target) after upstream PRs merge. Handles conflict resolution, squashes to a single commit, and runs autonomously
argument-hint: <target>
user-invocable: true
allowed-tools: Read, Write, AskUserQuestion, Bash(git branch *), Bash(git fetch *), Bash(git log *), Bash(git diff *), Bash(git rebase *), Bash(git reset *), Bash(git commit *), Bash(git add *), Bash(git checkout *), Bash(git merge-base *), Bash(git rev-parse *), Bash(git status *), Bash(git apply *), Bash(*/skills/issue-context/claude-work-root.sh *), Bash(*/skills/rebase-issue/resolve-commit-msg.sh *)
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

If `$ARGUMENTS` was provided, use it as the target ref. Otherwise, resolve the target automatically from the base-branch marker:

1. Read the base-branch marker. Resolve the absolute path via `claude-work-root.sh`, then read `<base>/issues/<NUMBER>/base-branch` (written by `/start-issue`). If the marker is missing or unreadable, default to `origin/main`.
2. Check whether the recorded base branch still exists remotely:

   ```bash
   git ls-remote origin <base-branch>
   ```

3. If the remote ref exists (non-empty output), the base PR hasn't been merged yet. Use the recorded base branch as the target and record the mode as **stacked** for use in Steps 7 and 10.
4. If the remote ref does not exist (empty output), the base PR was merged and the branch was deleted. Fall back to `origin/main` in normal mode.

Accept any valid git ref as an explicit argument: `origin/main`, `main`, another issue branch, and so on. An explicit argument always wins over the marker file.

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

## Step 7: Rebase (Normal Mode) or Diff-Apply (Stacked Mode)

**Normal mode** (target is `origin/main` or any non-`issues/*` ref):

```bash
git rebase <target>
```

**Stacked mode** (base branch still exists remotely, determined in Step 3):

Skip `git rebase` entirely. Replaying every commit from the stacked branch's history contaminates the diff with old-commit residue whose changes already exist in the squashed base. Instead, apply only the unique stacked diff:

1. Save current HEAD to a temp branch ref so it survives the reset:

   ```bash
   git branch tmp-rebase-stacked-HEAD
   ```

2. Capture the unique diff — everything on the stacked branch that is not on the target:

   ```bash
   git diff <target>..tmp-rebase-stacked-HEAD > /tmp/stacked-diff.patch
   ```

3. Start clean from the base tip:

   ```bash
   git reset --hard <target>
   ```

4. Apply the unique changes:

   ```bash
   git apply /tmp/stacked-diff.patch
   ```

5. If `git apply` succeeds, stage the applied changes and clean up the temp ref:

   ```bash
   git add -A
   git branch -D tmp-rebase-stacked-HEAD
   ```

6. If `git apply` fails (the diff doesn't apply cleanly), resolve manually. The diff contains only the stacked branch's unique changes — it's small and focused. Inspect the rejected hunks, hand-apply the changes, then stage and clean up:

   ```bash
   git add -A
   git branch -D tmp-rebase-stacked-HEAD
   ```

Proceed to Step 9. Skip Step 8 — the conflict resolution strategy in Step 8 targets `git rebase` conflicts; stacked-mode apply failures are resolved inline above.

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

**Normal mode:**

```bash
git reset --soft <target>
```

All changes are now staged as a single diff, ready for one commit.

**Stacked mode:** changes are already staged from the diff apply in Step 7. Verify the staging looks correct:

```bash
git diff --cached --stat
```

Confirm only the expected unique stacked changes are present, then proceed to Step 11.

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
- **Stacked PRs:** when the base-branch marker file records another `issues/*` branch that still exists remotely (verified via `git ls-remote origin` in Step 3), `git rebase` is replaced with a diff-apply procedure (Step 7). The unique stacked diff is captured to a patch file, the branch is reset to the base tip, and only the unique changes are applied. This prevents contamination from old commits whose changes already exist in the squashed base. When the recorded base branch disappears from the remote (PR merged and branch deleted), the stacked branch automatically graduates to targeting `origin/main` in normal rebase mode.
- **Diff apply conflicts:** when `git apply` fails in stacked mode, resolve manually. The diff is limited to the stacked branch's unique changes, so conflicts are narrow and focused.
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
- [ ] Stacked mode (if applicable): temp ref created and cleaned up, unique diff captured and applied, no old-commit residue in staged changes
- [ ] Project formatter ran successfully
- [ ] Project test suite passes
- [ ] Changes squashed to a single commit on top of `<target>`
- [ ] Commit message sourced from pointer file, PR description, or git log fallback
- [ ] Push confirmed with the user before executing
