#!/usr/bin/env bats
#
# Tests for skills/cleanup-issue/remove-issue-dir.sh — safely removes an
# issue's working directory after validating the ID and base path.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/cleanup-issue/remove-issue-dir.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  # Create a realistic .claude-work/issues/ directory tree.
  mkdir -p "$TEST_TEMP_DIR/.claude-work/issues"
  BASE="$TEST_TEMP_DIR/.claude-work"
  # Pin settings to an empty object so the loader uses the built-in defaults
  # (segment "issues") regardless of the developer's real settings file.
  export MY_CLAUDE_SKILLS_CONFIG="$TEST_TEMP_DIR/settings.json"
  printf '{}\n' > "$MY_CLAUDE_SKILLS_CONFIG"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# ============================================================================
# Usage errors
# ============================================================================

@test "missing arguments prints usage error" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R002"* ]]
}

@test "single argument prints usage error" {
  run "$SCRIPT" "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R002"* ]]
}

# ============================================================================
# Base validation
# ============================================================================

@test "rejects base that doesn't end in /.claude-work" {
  mkdir -p "$TEST_TEMP_DIR/somewhere"
  run "$SCRIPT" "$TEST_TEMP_DIR/somewhere" "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R002"* ]]
}

@test "rejects relative base path" {
  # Create a directory at the relative path so the existence check passes.
  mkdir -p "$TEST_TEMP_DIR/not-claude-work"
  cd "$TEST_TEMP_DIR"
  run "$SCRIPT" "not-claude-work" "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R002"* ]]
}

@test "rejects non-existent base directory" {
  run "$SCRIPT" "$TEST_TEMP_DIR/.claude-work-nonexistent" "42"
  [ "$status" -eq 2 ]
  [[ "$output" == *"R002"* ]]
}

# ============================================================================
# ID validation
# ============================================================================

@test "rejects dot-only ID (.)" {
  run "$SCRIPT" "$BASE" "."
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

@test "rejects dot-dot ID (..)" {
  run "$SCRIPT" "$BASE" ".."
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

@test "rejects ID with slash" {
  run "$SCRIPT" "$BASE" "foo/bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

@test "rejects ID with space" {
  run "$SCRIPT" "$BASE" "foo bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

@test "rejects ID starting with hyphen" {
  run "$SCRIPT" "$BASE" "-foo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

@test "rejects ID with shell metacharacters" {
  run "$SCRIPT" "$BASE" '$(whoami)'
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

@test "rejects empty ID" {
  run "$SCRIPT" "$BASE" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

# ============================================================================
# Successful removals
# ============================================================================

@test "removes existing issue directory and prints path" {
  mkdir -p "$BASE/issues/42/scratchpads"
  touch "$BASE/issues/42/scratchpads/0001-plan.txt"
  [ -d "$BASE/issues/42" ]

  run "$SCRIPT" "$BASE" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE/issues/42" ]
  [ ! -d "$BASE/issues/42" ]
}

@test "idempotent: succeeds when issue directory does not exist" {
  [ ! -d "$BASE/issues/99" ]

  run "$SCRIPT" "$BASE" "99"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE/issues/99" ]
}

@test "idempotent: succeeds when issues/ parent directory does not exist" {
  # Simulates a .claude-work/ with no issues/ subdirectory at all.
  # The script must resolve the physical path from the base directory.
  rm -rf "$BASE/issues"
  [ ! -d "$BASE/issues" ]

  run "$SCRIPT" "$BASE" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE/issues/42" ]
}

@test "accepts alphanumeric and dot-hyphen IDs" {
  mkdir -p "$BASE/issues/rfc-auth-v2.test/notes"
  [ -d "$BASE/issues/rfc-auth-v2.test" ]

  run "$SCRIPT" "$BASE" "rfc-auth-v2.test"
  [ "$status" -eq 0 ]
  [ ! -d "$BASE/issues/rfc-auth-v2.test" ]
}

# ============================================================================
# Path traversal guard
# ============================================================================

@test "rejects ID that would escape via physical path" {
  # Create a symlink outside the .claude-work tree that points back in.
  mkdir -p "$TEST_TEMP_DIR/outside"
  ln -s "$TEST_TEMP_DIR/outside" "$BASE/issues/escape-hatch"

  run "$SCRIPT" "$BASE" "escape-hatch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

# ============================================================================
# Configurable segment
# ============================================================================

@test "non-default segment → removes under <base>/<segment>" {
  mkdir -p "$BASE/work/42"
  printf '{"segment":"work"}\n' > "$MY_CLAUDE_SKILLS_CONFIG"

  run "$SCRIPT" "$BASE" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE/work/42" ]
  [ ! -d "$BASE/work/42" ]
}

@test "empty segment → removes directly under <base>" {
  mkdir -p "$BASE/42"
  printf '{"segment":""}\n' > "$MY_CLAUDE_SKILLS_CONFIG"

  run "$SCRIPT" "$BASE" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE/42" ]
  [ ! -d "$BASE/42" ]
}

@test "empty segment → refuses a reserved category name as ID" {
  mkdir -p "$BASE/notes"
  printf '{"segment":""}\n' > "$MY_CLAUDE_SKILLS_CONFIG"

  run "$SCRIPT" "$BASE" "notes"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
  [ -d "$BASE/notes" ]
}

@test "empty segment → refuses ID escaping via physical path" {
  mkdir -p "$TEST_TEMP_DIR/outside"
  ln -s "$TEST_TEMP_DIR/outside" "$BASE/escape-hatch"
  printf '{"segment":""}\n' > "$MY_CLAUDE_SKILLS_CONFIG"

  run "$SCRIPT" "$BASE" "escape-hatch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}
