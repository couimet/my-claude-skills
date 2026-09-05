#!/usr/bin/env bats
#
# Tests for skills/issue-context/get-issue-folder-path.sh — prints the
# .claude-work/ folder that holds a work item's files, from an explicit
# identifier (--id) or inferred from the current branch. Every test runs in a
# fresh git repo with MY_CLAUDE_SKILLS_CONFIG pointed at a temp settings file.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/get-issue-folder-path.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  git checkout -q -B main
  # Default empty config — every key falls back to the built-in defaults.
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# Run the resolver with MY_CLAUDE_SKILLS_CONFIG pointing at the given config.
folder_with_config() {
  run env MY_CLAUDE_SKILLS_CONFIG="$1" "$SCRIPT" "${@:2}"
}

# ============================================================================
# --id resolution
# ============================================================================

@test "--id 42 → numeric folder under default issues segment" {
  folder_with_config "$CFG" --id 42
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42" ]
}

@test "--id PROJ-123 → key-shaped folder under default issues segment" {
  folder_with_config "$CFG" --id PROJ-123
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/PROJ-123" ]
}

@test "--id with a non-default segment → folder under that segment" {
  local cfg="$TEST_TEMP_DIR/nondefault.json"
  printf '%s' '{"segment":"work"}' > "$cfg"
  folder_with_config "$cfg" --id 42
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/work/42" ]
}

@test "--id with an omitted (empty) segment → no segment directory" {
  local cfg="$TEST_TEMP_DIR/empty-seg.json"
  printf '%s' '{"segment":""}' > "$cfg"
  folder_with_config "$cfg" --id 42
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/42" ]
}

@test "--id does not create the directory" {
  folder_with_config "$CFG" --id 42
  [ ! -d "$TEST_TEMP_DIR/.claude-work/issues/42" ]
}

@test "--id with an unsafe identifier errors" {
  folder_with_config "$CFG" --id ".hidden"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not usable"* ]]
}

# ============================================================================
# Branch inference
# ============================================================================

@test "issues/42 branch (no --id) → issues segment folder" {
  git checkout -q -b issues/42
  folder_with_config "$CFG"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42" ]
}

@test "issues/PROJ-123-add-config branch → key-shaped folder (new key-shaped row)" {
  git checkout -q -b issues/PROJ-123-add-config
  folder_with_config "$CFG"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/PROJ-123" ]
}

@test "PROJ-123-add-config branch (no issues/ prefix) → key-shaped folder (new top-level row)" {
  git checkout -q -b PROJ-123-add-config
  folder_with_config "$CFG"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/PROJ-123" ]
}

@test "main branch → flat root, no segment" {
  folder_with_config "$CFG"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
}

# ============================================================================
# Config plumbing
# ============================================================================

@test "override wins over a config at the HOME default path" {
  local home="$TEST_TEMP_DIR/home"
  mkdir -p "$home/.my-claude-skills"
  printf '%s' '{"segment":"homeval"}' > "$home/.my-claude-skills/settings.json"
  local cfg="$TEST_TEMP_DIR/override.json"
  printf '%s' '{"segment":"overrideval"}' > "$cfg"
  git checkout -q -b issues/42
  run env HOME="$home" MY_CLAUDE_SKILLS_CONFIG="$cfg" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/overrideval/42" ]
}

@test "malformed config → warning, falls back to default segment" {
  local cfg="$TEST_TEMP_DIR/malformed.json"
  printf '%s' '{"segment":' > "$cfg"
  folder_with_config "$cfg" --id 42
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning"* ]]
  [[ "$output" == *"$TEST_TEMP_DIR/.claude-work/issues/42" ]]
}
