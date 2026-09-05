---
name: add-github-dependency
version: 2026.09.03@a8dc4ea
description: Add a dependency relationship between GitHub issues using the native addBlockedBy mutation
argument-hint: <blocked-by|is-blocking> <issue-url>
user-invocable: true
allowed-tools: Read, Bash(*/skills/create-github-issue/link-dependency.sh *), Bash(*/skills/issue-context/branch-issue-id.sh *), Bash(gh repo view *)
---

# Add GitHub Dependency

Add a dependency relationship between GitHub issues using GitHub's native `addBlockedBy` mutation. Works cross-repo — node IDs are globally unique, so the mutation handles same-repo and cross-repo identically.

**Input:** `$ARGUMENTS` — a relationship type (`blocked-by` or `is-blocking`) followed by a target issue URL.

## Step 1: Parse Arguments

Split `$ARGUMENTS` on whitespace. The first token is the relationship type. The second token is the target issue URL.

Validate the relationship type:

```text
blocked-by   — the current issue IS BLOCKED BY the target issue
is-blocking  — the current issue IS BLOCKING the target issue
```

If the relationship type is not one of these two values, print an error and exit:

```text
add-github-dependency: invalid relationship type '<type>'. Expected 'blocked-by' or 'is-blocking'.
Usage: /add-github-dependency <blocked-by|is-blocking> <issue-url>
```

Parse the target URL to extract owner, repo, and issue number. The URL format is:

```text
https://github.com/<owner>/<repo>/issues/<number>
```

If the URL does not match this pattern, print an error and exit:

```text
add-github-dependency: could not parse issue URL '<url>'. Expected format: https://github.com/<owner>/<repo>/issues/<number>
```

## Step 2: Resolve Subject Issue

Resolve the current branch's identifier as the subject via `branch-issue-id.sh`:

```bash
~/.claude/skills/issue-context/branch-issue-id.sh
```

On exit 0, the printed identifier is the subject issue number (e.g., on `issues/182` it prints `182`). If it exits 1, the current branch is not a work branch; print an error and exit:

```text
add-github-dependency: current branch is not an issues/* branch. Switch to the issue branch for the subject issue first.
```

Determine the subject's owner and repo from the current git remote:

```bash
gh repo view --json owner,name
```

If this fails, print an error and exit:

```text
add-github-dependency: could not determine current repository. Run from within a git repository.
```

## Step 3: Link the Dependency

Call the unified linking script:

```bash
~/.claude/skills/create-github-issue/link-dependency.sh \
  --subject-owner "$SUBJECT_OWNER" \
  --subject-repo "$SUBJECT_REPO" \
  --subject-number "$SUBJECT_NUMBER" \
  --target-owner "$TARGET_OWNER" \
  --target-repo "$TARGET_REPO" \
  --target-number "$TARGET_NUMBER" \
  --relationship "$RELATIONSHIP"
```

Report the result:

**On success:** print the script's output line.

**On failure:** print the error and exit with:

```text
add-github-dependency: linking failed — <error message>
```

Formatting: see `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.
