#!/usr/bin/env bats
#
# Tests for skills/rebase-issue/resolve-commit-msg.sh — resolves the commit
# message for a rebased issue branch via three-tier fallback chain.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/rebase-issue/resolve-commit-msg.sh"

# Each test runs inside a fresh git repo so git log and claude-work-root.sh
# behave deterministically.
setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  cd "$TEST_TEMP_DIR"
  git init --initial-branch=main -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "initial commit"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# --- Helpers ---

# Write content to a file, creating parent directories as needed.
write_file() {
  local path="$1"
  local content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$content" > "$path"
}

# ============================================================================
# Argument validation
# ============================================================================

@test "missing all arguments prints error with C001" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C001"* ]]
  [[ "$output" == *"expected 2 arguments, got 0"* ]]
}

@test "missing target argument prints error with C001" {
  run "$SCRIPT" "" "42"
  [ "$status" -eq 1 ]
}

@test "missing issue-number argument prints error with C001" {
  run "$SCRIPT" "origin/main"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C001"* ]]
}

@test "too many arguments prints error with C001" {
  run "$SCRIPT" "origin/main" "42" "extra"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C001"* ]]
}

@test "empty issue number prints error with C001" {
  run "$SCRIPT" "origin/main" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"C001"* ]]
}

@test "issue number with slash prints error with C001" {
  run "$SCRIPT" "origin/main" "42/evil"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C001"* ]]
}

@test "usage text is printed on argument error" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

# ============================================================================
# Source 1: last-finish-issue pointer file
# ============================================================================

@test "pointer file points to readable PR description → content returned" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  local pr_desc="$issue_dir/notes/20260701-120000-finish-issue-42.txt"
  write_file "$pr_desc" "PR description content here"
  write_file "$issue_dir/last-finish-issue" "$pr_desc"

  run "$SCRIPT" "origin/main" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "PR description content here" ]
}

@test "pointer file with trailing newline still works" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  local pr_desc="$issue_dir/notes/20260701-120000-finish-issue-42.txt"
  write_file "$pr_desc" "PR description content"
  printf '%s\n' "$pr_desc" > "$issue_dir/last-finish-issue"

  run "$SCRIPT" "origin/main" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "PR description content" ]
}

@test "pointer points to nonexistent file → falls through to source 2" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/42"

  write_file "$issue_dir/last-finish-issue" "/nonexistent/path/pr-desc.txt"

  local note="$issue_dir/notes/20260701-120000-finish-issue-42.txt"
  write_file "$note" "fallback note content"

  run "$SCRIPT" "origin/main" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "fallback note content" ]
}

@test "pointer file is empty → falls through to source 2" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/42"

  write_file "$issue_dir/last-finish-issue" ""

  local note="$issue_dir/notes/20260701-120000-finish-issue-42.txt"
  write_file "$note" "fallback note content"

  run "$SCRIPT" "origin/main" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "fallback note content" ]
}

@test "pointer points to an empty file → falls through to source 2" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/42"

  local pr_desc="$issue_dir/notes/empty-desc.txt"
  write_file "$pr_desc" ""
  write_file "$issue_dir/last-finish-issue" "$pr_desc"

  local note="$issue_dir/notes/20260701-120000-finish-issue-42.txt"
  write_file "$note" "fallback note content"

  run "$SCRIPT" "origin/main" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "fallback note content" ]
}

# ============================================================================
# Source 2: find PR description in notes/ directory
# ============================================================================

@test "single matching note → content returned" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  local note="$issue_dir/notes/20260701-120000-finish-issue-42.txt"
  write_file "$note" "single note content"

  run "$SCRIPT" "origin/main" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "single note content" ]
}

@test "multiple notes → picks most recent (lexicographically last)" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/42"

  write_file "$issue_dir/notes/20260701-120000-some-other-note.txt" "wrong file"
  write_file "$issue_dir/notes/20260702-090000-finish-issue-42.txt" "older match"
  write_file "$issue_dir/notes/20260703-150000-finish-issue-42.txt" "newer match"
  write_file "$issue_dir/notes/20260704-080000-unrelated.txt" "nope"

  run "$SCRIPT" "origin/main" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "newer match" ]
}

@test "notes directory exists but no matching files → falls through to source 3" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$issue_dir/notes/unrelated-note.txt" "not a match"

  git checkout -q -b issues/42
  git commit --allow-empty -q -m "commit message from git log"

  run "$SCRIPT" "main" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"commit message from git log"* ]]
}

@test "notes directory does not exist → falls through to source 3" {
  git checkout -q -b issues/42
  git commit --allow-empty -q -m "commit from git log"

  run "$SCRIPT" "main" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"commit from git log"* ]]
}

@test "empty notes directory → falls through to source 3" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  mkdir -p "$issue_dir/notes"

  git checkout -q -b issues/42
  git commit --allow-empty -q -m "commit from git log"

  run "$SCRIPT" "main" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"commit from git log"* ]]
}

# ============================================================================
# Source 3: git log fallback
# ============================================================================

@test "git log captures commits on branch not on target" {
  git checkout -q -b issues/42
  git commit --allow-empty -q -m "issue work commit"

  run "$SCRIPT" "main" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"issue work commit"* ]]
}

@test "git log includes multi-paragraph commit messages" {
  git checkout -q -b issues/42
  git commit --allow-empty -q -m "First line of commit

Second paragraph of the commit message."

  run "$SCRIPT" "main" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"First line of commit"* ]]
  [[ "$output" == *"Second paragraph"* ]]
}

@test "git log captures multiple commits on branch" {
  git checkout -q -b issues/42
  git commit --allow-empty -q -m "first issue commit"
  git commit --allow-empty -q -m "second issue commit"

  run "$SCRIPT" "main" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"first issue commit"* ]]
  [[ "$output" == *"second issue commit"* ]]
}

@test "git log with no divergence → all sources empty" {
  run "$SCRIPT" "main" "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C004"* ]]
  [[ "$output" == *"all commit message sources are empty"* ]]
}

# ============================================================================
# Edge cases and combined scenarios
# ============================================================================

@test "all sources empty → exits 1 with C004" {
  run "$SCRIPT" "origin/main" "99"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C004"* ]]
}

@test "non-numeric issue number works (e.g., rfc-auth)" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/rfc-auth"
  local note="$issue_dir/notes/20260701-120000-finish-issue-rfc-auth.txt"
  write_file "$note" "RFC auth plan"

  run "$SCRIPT" "origin/main" "rfc-auth"
  [ "$status" -eq 0 ]
  [ "$output" = "RFC auth plan" ]
}

@test "source 1 wins over source 2 when both are available" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/42"

  local pr_desc="$issue_dir/notes/pr-desc.txt"
  write_file "$pr_desc" "pointer content"
  write_file "$issue_dir/last-finish-issue" "$pr_desc"

  write_file "$issue_dir/notes/20260701-120000-finish-issue-42.txt" "note content"

  run "$SCRIPT" "origin/main" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "pointer content" ]
}

@test "source 2 wins over source 3 when pointer is missing" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/42"

  write_file "$issue_dir/notes/20260701-120000-finish-issue-42.txt" "note content"

  git checkout -q -b issues/42
  git commit --allow-empty -q -m "git log content"

  run "$SCRIPT" "origin/main" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "note content" ]
}

@test "pointer with whitespace in path is handled" {
  local issue_dir="$TEST_TEMP_DIR/.claude-work/issues/42"

  local pr_desc="$issue_dir/notes/my pr description.txt"
  write_file "$pr_desc" "content with spaces path"
  write_file "$issue_dir/last-finish-issue" "$pr_desc"

  run "$SCRIPT" "origin/main" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "content with spaces path" ]
}

@test "target ref that does not exist → git log skipped, falls to C004" {
  run "$SCRIPT" "nonexistent-ref" "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C004"* ]]
}

@test "not in a git repository → exits 1" {
  cd /tmp
  run "$SCRIPT" "origin/main" "42"
  [ "$status" -eq 1 ]
}
