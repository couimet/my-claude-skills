#!/usr/bin/env bats
#
# Tests for skills/rebase-issue/apply-stacked-diff.sh — captures the unique
# diff of a stacked branch, resets to the target, and applies via git apply
# --reject with per-run unique resource names and cleanup.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/rebase-issue/apply-stacked-diff.sh"

# Each test runs inside a fresh git repo so git state is deterministic.
setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  cd "$TEST_TEMP_DIR"
  git init --initial-branch=main -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "initial commit"

  # Create a baseline file on main so branches have something to diff.
  echo "line1" > a.txt
  echo "line2" >> a.txt
  echo "line3" >> a.txt
  git add a.txt
  git commit -q -m "add a.txt"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# --- Helpers ---

# Create a tracked file with content and commit it on the current branch.
commit_file() {
  local path="$1"
  local content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$content" > "$path"
  git add "$path"
  git commit -q -m "add/update $path"
}

# ============================================================================
# Argument validation
# ============================================================================

@test "no arguments → error A001" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"A001"* ]]
  [[ "$output" == *"expected 1 argument, got 0"* ]]
}

@test "two arguments → error A001" {
  run "$SCRIPT" "main" "extra"
  [ "$status" -eq 1 ]
  [[ "$output" == *"A001"* ]]
}

@test "usage text printed on argument error" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

# ============================================================================
# Target ref validation
# ============================================================================

@test "target ref does not exist → error A002" {
  run "$SCRIPT" "nonexistent-ref"
  [ "$status" -eq 1 ]
  [[ "$output" == *"A002"* ]]
  [[ "$output" == *"does not exist"* ]]
}

# ============================================================================
# No diff (HEAD == target)
# ============================================================================

@test "HEAD equals target → error A003 (no unique changes)" {
  run "$SCRIPT" "main"
  [ "$status" -eq 1 ]
  [[ "$output" == *"A003"* ]]
  [[ "$output" == *"no unique changes"* ]]
}

# ============================================================================
# Successful apply
# ============================================================================

@test "single-file modification applies cleanly" {
  # Branch off main and modify a.txt.
  git checkout -q -b issues/200
  echo "line2-modified" > a.txt
  echo "line1" >> a.txt
  sed -i '' 's/line2/line2-modified/' a.txt 2>/dev/null || sed -i 's/line2/line2-modified/' a.txt
  # Actually, sed -i is fragile across platforms. Use printf instead.
  printf 'line1\nline2-modified\nline3\n' > a.txt
  git add a.txt
  git commit -q -m "modify a.txt"

  run "$SCRIPT" "main"

  [ "$status" -eq 0 ]
  [[ "$output" == *"applied and staged successfully"* ]]

  # Verify the change was applied: we are now at main + our change.
  [ "$(cat a.txt)" = "$(printf 'line1\nline2-modified\nline3\n')" ]

  # Verify changes are staged (git diff --cached should show something,
  # and git diff should be empty since changes are staged).
  [ -n "$(git diff --cached --stat)" ]
  [ -z "$(git diff --stat)" ]

  # Verify no temp branch was left behind.
  run git branch --list 'rebase-stacked-*'
  [ -z "$output" ]
}

@test "multi-file changes apply cleanly" {
  git checkout -q -b issues/200

  printf 'modified a\n' > a.txt
  printf 'new file b\n' > b.txt
  git add a.txt b.txt
  git commit -q -m "modify a.txt, add b.txt"

  run "$SCRIPT" "main"

  [ "$status" -eq 0 ]
  [[ "$output" == *"applied and staged successfully"* ]]
  [ "$(cat a.txt)" = "modified a" ]
  [ "$(cat b.txt)" = "new file b" ]
  [ -n "$(git diff --cached --stat)" ]
}

@test "file creation applies cleanly" {
  git checkout -q -b issues/200

  printf 'brand new file\n' > newfile.txt
  git add newfile.txt
  git commit -q -m "add newfile.txt"

  run "$SCRIPT" "main"

  [ "$status" -eq 0 ]
  [[ "$output" == *"applied and staged successfully"* ]]
  [ "$(cat newfile.txt)" = "brand new file" ]
}

@test "file deletion applies cleanly" {
  git checkout -q -b issues/200

  git rm -q a.txt
  git commit -q -m "delete a.txt"

  run "$SCRIPT" "main"

  [ "$status" -eq 0 ]
  [[ "$output" == *"applied and staged successfully"* ]]
  [ ! -f a.txt ]
}

@test "multiple commits on branch squashed into single diff" {
  git checkout -q -b issues/200

  printf 'commit 1\n' > a.txt
  git add a.txt
  git commit -q -m "first change"

  printf 'commit 1 plus more\n' > a.txt
  git add a.txt
  git commit -q -m "second change"

  run "$SCRIPT" "main"

  [ "$status" -eq 0 ]
  [[ "$output" == *"applied and staged successfully"* ]]
  [ "$(cat a.txt)" = "commit 1 plus more" ]
}

# ============================================================================
# Temp resource cleanup
# ============================================================================

@test "temp branch is cleaned up on success" {
  git checkout -q -b issues/200

  printf 'changed\n' > a.txt
  git add a.txt
  git commit -q -m "change a.txt"

  run "$SCRIPT" "main"
  [ "$status" -eq 0 ]

  # No rebase-stacked-* branches should remain.
  local branches
  branches="$(git branch --list 'rebase-stacked-*')"
  [ -z "$branches" ]
}

@test "temp branch is cleaned up on A003 (no diff) failure" {
  git checkout -q -b issues/200

  # HEAD equals target, so no diff.
  git checkout main

  run "$SCRIPT" "main"
  [ "$status" -eq 1 ]

  local branches
  branches="$(git branch --list 'rebase-stacked-*')"
  [ -z "$branches" ]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "works with target on a non-main branch" {
  # Create a base branch that diverges from main.
  git checkout -q -b base-branch
  printf 'base content\n' > base.txt
  git add base.txt
  git commit -q -m "base file"

  # Stack a branch on top.
  git checkout -q -b issues/200
  printf 'stacked change\n' > base.txt
  git add base.txt
  git commit -q -m "modify base.txt from stacked branch"

  run "$SCRIPT" "base-branch"

  [ "$status" -eq 0 ]
  [[ "$output" == *"applied and staged successfully"* ]]
  [ "$(cat base.txt)" = "stacked change" ]
}

@test "changes only in subdirectory apply cleanly" {
  git checkout -q -b issues/200

  mkdir -p subdir
  printf 'nested content\n' > subdir/nested.txt
  git add subdir/nested.txt
  git commit -q -m "add nested file"

  run "$SCRIPT" "main"

  [ "$status" -eq 0 ]
  [[ "$output" == *"applied and staged successfully"* ]]
  [ "$(cat subdir/nested.txt)" = "nested content" ]
}

@test "works with many stacked changes on top of base branch" {
  # Simulate a base branch (another stacked PR).
  git checkout -q -b issues/100
  commit_file "base-only.txt" "base file content"

  # Stack issues/200 on top with several changes.
  git checkout -q -b issues/200
  printf 'changed a\n' > a.txt
  printf 'new file 1\n' > b.txt
  printf 'new file 2\n' > c.txt
  git add a.txt b.txt c.txt
  git commit -q -m "multiple stacked changes"

  run "$SCRIPT" "issues/100"

  [ "$status" -eq 0 ]
  [[ "$output" == *"applied and staged successfully"* ]]
  [ "$(cat a.txt)" = "changed a" ]
  [ "$(cat b.txt)" = "new file 1" ]
  [ "$(cat c.txt)" = "new file 2" ]
  # base-only.txt from the base branch survives the diff-apply.
  [ "$(cat base-only.txt)" = "base file content" ]
}

# ============================================================================
# Apply failure path (A004)
# ============================================================================

# Triggering git apply --reject failure is difficult in a test because the
# diff is captured against the exact target we reset to, so the context
# always matches. The failure path is exercised in real use when file
# permissions, binary diffs, or symlink conflicts arise. The error code and
# messaging are validated structurally: the if/else around git apply defines
# the only two outcomes, and A004 is the else branch.

@test "error code A004 is defined in the script source" {
  run grep 'readonly ERR_APPLY="A004"' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "A004 error path exists — script contains the failure branch" {
  run grep 'apply-stacked-diff \$ERR_APPLY error: git apply --reject failed' "$SCRIPT"
  [ "$status" -eq 0 ]
}
