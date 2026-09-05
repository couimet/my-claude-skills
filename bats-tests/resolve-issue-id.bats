#!/usr/bin/env bats
#
# Tests for skills/issue-context/resolve-issue-id.sh — resolves a tracker URL
# or bare identifier to a canonical work-item identifier. Every test points
# MY_CLAUDE_SKILLS_CONFIG at a temp settings file so a developer's real
# ~/.my-claude-skills/settings.json can never change the outcome.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/resolve-issue-id.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  # Default empty config — every key falls back to the built-in defaults with
  # no warning.
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
}

# Run the resolver with MY_CLAUDE_SKILLS_CONFIG pointing at the given config.
resolve_with_config() {
  run env MY_CLAUDE_SKILLS_CONFIG="$1" "$SCRIPT" "${@:2}"
}

# ============================================================================
# URL resolution against the default urlPatterns
# ============================================================================

@test "GitHub issues URL → numeric id" {
  resolve_with_config "$CFG" "https://github.com/couimet/my-claude-skills/issues/248"
  [ "$status" -eq 0 ]
  [ "$output" = "248" ]
}

@test "Jira browse URL → key-shaped id" {
  resolve_with_config "$CFG" "https://jira.example.com/browse/PROJ-123"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-123" ]
}

# ============================================================================
# Bare identifier pass-through
# ============================================================================

@test "bare numeric identifier passes through" {
  resolve_with_config "$CFG" "42"
  [ "$status" -eq 0 ]
  [ "$output" = "42" ]
}

@test "bare key-shaped identifier passes through" {
  resolve_with_config "$CFG" "PROJ-123"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-123" ]
}

# ============================================================================
# Custom urlPatterns from the config
# ============================================================================

@test "custom urlPatterns resolve in order, first match wins" {
  local cfg="$TEST_TEMP_DIR/custom.json"
  printf '%s' '{"urlPatterns":["/tickets/([0-9]+)","/cases/([A-Z]+-[0-9]+)"]}' > "$cfg"
  # Second pattern matches where the first does not.
  resolve_with_config "$cfg" "https://tracker.example.com/cases/ABC-7"
  [ "$status" -eq 0 ]
  [ "$output" = "ABC-7" ]
}

@test "custom urlPatterns replace defaults, so a GitHub URL now errors" {
  local cfg="$TEST_TEMP_DIR/custom.json"
  printf '%s' '{"urlPatterns":["/tickets/([0-9]+)"]}' > "$cfg"
  resolve_with_config "$cfg" "https://github.com/couimet/my-claude-skills/issues/248"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no url pattern matched"* ]]
}

# ============================================================================
# Rejection paths
# ============================================================================

@test "URL-shaped value matching no pattern errors" {
  resolve_with_config "$CFG" "https://example.com/tickets/123"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no url pattern matched"* ]]
}

@test "bare identifier with leading dot errors" {
  resolve_with_config "$CFG" ".hidden"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not usable"* ]]
}

@test "bare identifier with whitespace errors" {
  resolve_with_config "$CFG" "foo bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not usable"* ]]
}

@test "missing argument prints usage and errors" {
  resolve_with_config "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* ]]
}
