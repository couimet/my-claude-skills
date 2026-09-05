#!/usr/bin/env bats
#
# Tests for skills/issue-context/branch-issue-id.sh — matches the current git
# branch against branchPatterns and prints the identifier (capture group one)
# of the first matching pattern. A non-matching branch exits 1 silently.
# Every test runs in a fresh git repo with MY_CLAUDE_SKILLS_CONFIG pointed at
# a temp settings file, so a developer's personal settings never leak in.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/branch-issue-id.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  # Default empty config — every key falls back to the built-in defaults.
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# Check out the branch, then run the gate against the given config.
run_on_branch() {
  local branch_name="$1"
  local cfg="${2:-$CFG}"
  git checkout -q -b "$branch_name"
  run env MY_CLAUDE_SKILLS_CONFIG="$cfg" "$SCRIPT"
}

# ============================================================================
# Default branchPatterns — all five rows
# ============================================================================

@test "issues/42 → numeric id" {
  run_on_branch "issues/42"
  [ "$status" -eq 0 ]
  [ "$output" = "42" ]
}

@test "issues/120-audit-cleanup → numeric prefix before dash" {
  run_on_branch "issues/120-audit-cleanup"
  [ "$status" -eq 0 ]
  [ "$output" = "120" ]
}

@test "issues/120_audit → numeric prefix before underscore" {
  run_on_branch "issues/120_audit"
  [ "$status" -eq 0 ]
  [ "$output" = "120" ]
}

@test "issues/PROJ-123-add-config → key-shaped id (new key-shaped row)" {
  run_on_branch "issues/PROJ-123-add-config"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-123" ]
}

@test "PROJ-123-add-config (no issues/ prefix) → key-shaped id (new top-level row)" {
  run_on_branch "PROJ-123-add-config"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-123" ]
}

@test "issues/rfc-auth → full slug after issues/" {
  run_on_branch "issues/rfc-auth"
  [ "$status" -eq 0 ]
  [ "$output" = "rfc-auth" ]
}

# ============================================================================
# Non-matching branches exit 1 silently
# ============================================================================

@test "main → exit 1 with no output" {
  git checkout -q -B main
  run env MY_CLAUDE_SKILLS_CONFIG="$CFG" "$SCRIPT"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "non-matching branch name → exit 1 with no output" {
  git checkout -q -b "chore/some-trunk"
  run env MY_CLAUDE_SKILLS_CONFIG="$CFG" "$SCRIPT"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "detached HEAD → exit 1 with no output" {
  git checkout -q --detach
  run env MY_CLAUDE_SKILLS_CONFIG="$CFG" "$SCRIPT"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# ============================================================================
# Custom branchPatterns
# ============================================================================

@test "custom branchPatterns replace defaults" {
  local cfg="$TEST_TEMP_DIR/custom.json"
  printf '%s' '{"branchPatterns":["^feature/([A-Z]+-[0-9]+)"]}' > "$cfg"
  run_on_branch "feature/ABC-7" "$cfg"
  [ "$status" -eq 0 ]
  [ "$output" = "ABC-7" ]
}

@test "custom branchPatterns replace defaults, so issues/42 no longer matches" {
  local cfg="$TEST_TEMP_DIR/custom.json"
  printf '%s' '{"branchPatterns":["^feature/([A-Z]+-[0-9]+)"]}' > "$cfg"
  run_on_branch "issues/42" "$cfg"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
