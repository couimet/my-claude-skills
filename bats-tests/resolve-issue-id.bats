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

@test "bare identifier with an internal slash errors" {
  resolve_with_config "$CFG" "foo/bar/baz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not usable"* ]]
}

@test "bare dotdot traversal errors" {
  resolve_with_config "$CFG" "foo/../../outside"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not usable"* ]]
}

@test "bare dotdot alone errors" {
  resolve_with_config "$CFG" ".."
  [ "$status" -eq 1 ]
  [[ "$output" == *"not usable"* ]]
}

@test "URL capture containing a slash is refused, not printed" {
  local cfg="$TEST_TEMP_DIR/capture.json"
  printf '%s' '{"urlPatterns":["/items/(.+)"]}' > "$cfg"
  # Capture group one is "foo/bar", which is not a single path component.
  resolve_with_config "$cfg" "https://tracker.example.com/items/foo/bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no url pattern matched"* ]]
}

@test "missing argument prints usage and errors" {
  resolve_with_config "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* ]]
}

# ============================================================================
# identifierCase folding
# ============================================================================

@test "bare lowercase key → folded to uppercase by default" {
  resolve_with_config "$CFG" "proj-1234"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-1234" ]
}

@test "lowercase Jira browse URL → resolves and folds to uppercase" {
  # Before this, the uppercase-only default urlPattern refused the URL outright
  # while the same key typed bare resolved: the asymmetry issues/262 opens on.
  resolve_with_config "$CFG" "https://jira.example.com/browse/proj-1234"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-1234" ]
}

@test "URL and bare identifier for one ticket resolve to the same value" {
  resolve_with_config "$CFG" "https://jira.example.com/browse/proj-1234"
  local from_url="$output"
  resolve_with_config "$CFG" "PROJ-1234"
  [ "$output" = "$from_url" ]
}

@test "bare key under lower → folded to lowercase" {
  local cfg="$TEST_TEMP_DIR/lower.json"
  printf '%s' '{"identifierCase":"lower"}' > "$cfg"
  resolve_with_config "$cfg" "PROJ-1234"
  [ "$status" -eq 0 ]
  [ "$output" = "proj-1234" ]
}

@test "URL capture under lower → folded to lowercase" {
  local cfg="$TEST_TEMP_DIR/lower.json"
  printf '%s' '{"identifierCase":"lower"}' > "$cfg"
  resolve_with_config "$cfg" "https://jira.example.com/browse/PROJ-1234"
  [ "$status" -eq 0 ]
  [ "$output" = "proj-1234" ]
}

@test "bare key under preserve → left alone" {
  local cfg="$TEST_TEMP_DIR/preserve.json"
  printf '%s' '{"identifierCase":"preserve"}' > "$cfg"
  resolve_with_config "$cfg" "proj-1234"
  [ "$status" -eq 0 ]
  [ "$output" = "proj-1234" ]
}

@test "GitHub numeric id is never folded" {
  resolve_with_config "$CFG" "https://github.com/couimet/my-claude-skills/issues/262"
  [ "$status" -eq 0 ]
  [ "$output" = "262" ]
}

@test "bare free-form slug is never folded" {
  resolve_with_config "$CFG" "my-feature"
  [ "$status" -eq 0 ]
  [ "$output" = "my-feature" ]
}
