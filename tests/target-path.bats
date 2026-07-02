#!/usr/bin/env bats
#
# Tests for skills/issue-context/target-path.sh — resolves the full target
# path for a numbered working file by combining branch detection, issue-ID
# extraction, slug derivation, and auto-numbering.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/target-path.sh"

# Run the script inside a fresh git repo so branch detection is deterministic.
setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  # Resolve any symlinks (macOS /var → /private/var) so path comparisons
  # against git rev-parse --show-toplevel output match exactly.
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# ============================================================================
# Issue branches: path includes the issue ID
# ============================================================================

@test "issues/42 → numeric ID, scratchpads type" {
  git checkout -q -b issues/42
  run "$SCRIPT" --type scratchpads --description "Plan the refactor"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/0001-plan-the-refactor.txt" ]
}

@test "issues/120-extract-numeric-prefix → extracts 120" {
  git checkout -q -b issues/120-audit-cleanup
  run "$SCRIPT" --type questions --description "Scope question"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/120/questions/0001-scope-question.txt" ]
}

@test "issues/120_with_underscore → extracts 120" {
  git checkout -q -b issues/120_audit
  run "$SCRIPT" --type scratchpads --description "Test"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/120/scratchpads/0001-test.txt" ]
}

@test "issues/rfc-auth → non-numeric prefix uses full segment" {
  git checkout -q -b issues/rfc-auth
  run "$SCRIPT" --type commit-msgs --description "Draft message"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/rfc-auth/commit-msgs/0001-draft-message.txt" ]
}

# ============================================================================
# Non-issue branches: path goes to flat root
# ============================================================================

@test "main branch → flat-root placement" {
  # Force the branch name so the test is deterministic regardless of the host's
  # init.defaultBranch setting (which may be master, main, trunk, etc.).
  git checkout -q -B main
  run "$SCRIPT" --type scratchpads --description "Hello world"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/scratchpads/0001-hello-world.txt" ]
}

@test "side-quest/foo branch → flat-root placement" {
  git checkout -q -b side-quest/foo
  run "$SCRIPT" --type questions --description "Side quest question"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/questions/0001-side-quest-question.txt" ]
}

# ============================================================================
# Auto-numbering advances
# ============================================================================

@test "second call increments NNNN" {
  git checkout -q -b issues/42
  run "$SCRIPT" --type scratchpads --description "First"
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/0001-first.txt" ]
  # Create the file so auto-number sees it on the next call
  touch ".claude-work/issues/42/scratchpads/0001-first.txt"
  run "$SCRIPT" --type scratchpads --description "Second"
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/0002-second.txt" ]
}

# ============================================================================
# Slug normalization
# ============================================================================

@test "slug lowercases, hyphenates, and collapses separators" {
  git checkout -q -b issues/42
  run "$SCRIPT" --type scratchpads --description "Some   MIXED--Case & punctuation!"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/0001-some-mixed-case-punctuation.txt" ]
}

@test "slug trims leading and trailing hyphens" {
  git checkout -q -b issues/42
  run "$SCRIPT" --type scratchpads --description "  hello world  "
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/0001-hello-world.txt" ]
}

# ============================================================================
# Extension override
# ============================================================================

@test "--ext overrides default txt extension" {
  git checkout -q -B main
  run "$SCRIPT" --type scratchpads --description "Config" --ext json
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/scratchpads/0001-config.json" ]
}

@test "--ext md still works alongside json" {
  git checkout -q -B main
  run "$SCRIPT" --type scratchpads --description "Doc" --ext md
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/scratchpads/0001-doc.md" ]
}

# ============================================================================
# --ext validation: reject anything that isn't pure alphanumeric
# ============================================================================

@test "--ext with dots (..) errors with T102" {
  run "$SCRIPT" --type scratchpads --description "x" --ext ".."
  [ "$status" -eq 1 ]
  [[ "$output" == *"T102"* ]]
}

@test "--ext with path separator errors with T102" {
  run "$SCRIPT" --type scratchpads --description "x" --ext "foo/bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T102"* ]]
}

@test "--ext with whitespace errors with T102" {
  run "$SCRIPT" --type scratchpads --description "x" --ext "foo bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T102"* ]]
}

@test "--ext with glob character errors with T102" {
  run "$SCRIPT" --type scratchpads --description "x" --ext "*"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T102"* ]]
}

@test "--ext with shell metacharacter errors with T102" {
  run "$SCRIPT" --type scratchpads --description "x" --ext '$(whoami)'
  [ "$status" -eq 1 ]
  [[ "$output" == *"T102"* ]]
}

@test "--ext with hyphen (not alphanumeric) errors with T102" {
  run "$SCRIPT" --type scratchpads --description "x" --ext "tar-gz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T102"* ]]
}

# ============================================================================
# Side effect: target directory is created
# ============================================================================

@test "--mkdir behavior: target directory is created on first call" {
  git checkout -q -b issues/77
  [ ! -d ".claude-work/issues/77/scratchpads" ]
  run "$SCRIPT" --type scratchpads --description "First"
  [ "$status" -eq 0 ]
  [ -d ".claude-work/issues/77/scratchpads" ]
}

# ============================================================================
# Error cases
# ============================================================================

@test "missing --type errors with T001" {
  run "$SCRIPT" --description "test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T001"* ]]
}

@test "missing --description errors with T001" {
  run "$SCRIPT" --type scratchpads
  [ "$status" -eq 1 ]
  [[ "$output" == *"T001"* ]]
}

@test "notes type on issue branch → issue-scoped notes path" {
  git checkout -q -b issues/42
  run "$SCRIPT" --type notes --description "Plan the work"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/notes/0001-plan-the-work.txt" ]
}

@test "notes type on main branch → flat-root notes path" {
  git checkout -q -B main
  run "$SCRIPT" --type notes --description "Quick finding"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/notes/0001-quick-finding.txt" ]
}

@test "invalid --type errors with T100" {
  run "$SCRIPT" --type bogus --description "test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T100"* ]]
}

@test "unknown flag errors with T002" {
  run "$SCRIPT" --type scratchpads --description "test" --nonsense
  [ "$status" -eq 1 ]
  [[ "$output" == *"T002"* ]]
}

# ============================================================================
# Linked worktree: output resolves to main checkout, not worktree local
# ============================================================================

@test "linked worktree: output resolves to main checkout .claude-work" {
  # Main checkout stays on the default branch; create a linked worktree
  # on issues/99 so the branch is not already checked out.
  git worktree add "$TEST_TEMP_DIR/wt-linked" -b issues/99 -q
  cd "$TEST_TEMP_DIR/wt-linked"
  run "$SCRIPT" --type notes --description "from worktree"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/99/notes/0001-from-worktree.txt" ]
  # Worktree directory should NOT have its own .claude-work
  [ ! -d "$TEST_TEMP_DIR/wt-linked/.claude-work" ]
}

# ============================================================================
# Repo-root anchoring: output is an absolute path independent of CWD
# ============================================================================

@test "subdirectory CWD: output path is absolute, independent of CWD" {
  mkdir -p subdir
  cd subdir
  run "$SCRIPT" --type notes --description "from subdir"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/notes/0001-from-subdir.txt" ]
  [ -d "$TEST_TEMP_DIR/.claude-work/notes" ]
  [ ! -d "$TEST_TEMP_DIR/subdir/.claude-work" ]
}
