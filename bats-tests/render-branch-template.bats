#!/usr/bin/env bats
#
# Tests for skills/issue-context/render-branch-template.sh — prints a branch
# name built from the configured branchTemplate, substituting {id} with the
# identifier, and rejects a rendered branch the configured branchPatterns do
# not parse back to the same identifier (branchTemplate and branchPatterns
# must be a paired configuration). Every test points MY_CLAUDE_SKILLS_CONFIG
# at a temp settings file so a developer's real ~/.my-claude-skills/settings.json
# can never change the outcome.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/render-branch-template.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  # Default empty config — every key falls back to the built-in defaults.
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# Render with MY_CLAUDE_SKILLS_CONFIG pointing at the given config.
render_with_config() {
  run env MY_CLAUDE_SKILLS_CONFIG="$1" "$SCRIPT" "${@:2}"
}

# ============================================================================
# Default template fallback
# ============================================================================

@test "default config → issues/{id} template, numeric id substituted" {
  render_with_config "$CFG" 42
  [ "$status" -eq 0 ]
  [ "$output" = "issues/42" ]
}

@test "key-shaped id renders under the default template" {
  render_with_config "$CFG" PROJ-123
  [ "$status" -eq 0 ]
  [ "$output" = "issues/PROJ-123" ]
}

@test "slug id renders under the default template" {
  render_with_config "$CFG" rfc-auth
  [ "$status" -eq 0 ]
  [ "$output" = "issues/rfc-auth" ]
}

# ============================================================================
# Custom branchTemplate
# ============================================================================

@test "custom branchTemplate with a matching branchPatterns entry → {id} substituted into it" {
  local cfg="$TEST_TEMP_DIR/custom.json"
  printf '%s' '{"branchTemplate":"feature/{id}","branchPatterns":["^feature/([0-9]+)$"]}' > "$cfg"
  render_with_config "$cfg" 42
  [ "$status" -eq 0 ]
  [ "$output" = "feature/42" ]
}

@test "custom branchTemplate paired with branchPatterns fully replaces the default" {
  local cfg="$TEST_TEMP_DIR/custom.json"
  printf '%s' '{"branchTemplate":"feature/{id}","branchPatterns":["^feature/([0-9]+)$"]}' > "$cfg"
  # The default template no longer applies: the custom one fully replaces it.
  render_with_config "$cfg" 42
  [ "$status" -eq 0 ]
  [ "$output" != "issues/42" ]
}

@test "template-only override under default patterns → rejected as unpaired" {
  local cfg="$TEST_TEMP_DIR/unpaired.json"
  printf '%s' '{"branchTemplate":"work/{id}"}' > "$cfg"
  # A branch the default branchPatterns cannot re-parse would be created by
  # /start-issue and then treated as a non-work branch by branch-issue-id.sh.
  render_with_config "$cfg" 42
  [ "$status" -eq 1 ]
  [[ "$output" == *"paired configuration"* ]]
}

@test "branch that re-parses to a different id → rejected as unpaired" {
  # Under the default branchPatterns, issues/123-rfc resolves to 123 (the
  # numeric row wins), not to 123-rfc, so the digit-leading slug cannot
  # round-trip and must not render.
  render_with_config "$CFG" 123-rfc
  [ "$status" -eq 1 ]
  [[ "$output" == *"paired configuration"* ]]
}

@test "paired branchTemplate + branchPatterns renders and round-trips" {
  local cfg="$TEST_TEMP_DIR/paired.json"
  printf '%s' '{"branchTemplate":"work/{id}","branchPatterns":["^work/([0-9]+)$"]}' > "$cfg"
  render_with_config "$cfg" 42
  [ "$status" -eq 0 ]
  [ "$output" = "work/42" ]
}

@test "template with no {id} placeholder → falls back to issues/{id}" {
  local cfg="$TEST_TEMP_DIR/noplaceholder.json"
  printf '%s' '{"branchTemplate":"fixed-branch"}' > "$cfg"
  render_with_config "$cfg" 42
  [ "$status" -eq 0 ]
  [ "$output" = "issues/42" ]
}

@test "explicit empty template → falls back to issues/{id}" {
  local cfg="$TEST_TEMP_DIR/emptytemplate.json"
  printf '%s' '{"branchTemplate":""}' > "$cfg"
  render_with_config "$cfg" 42
  [ "$status" -eq 0 ]
  [ "$output" = "issues/42" ]
}

# ============================================================================
# Identifier safety
# ============================================================================

@test "unsafe identifier → error on stderr, exit 1" {
  render_with_config "$CFG" ".hidden"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not usable"* ]]
}

@test "identifier with an internal slash → error, exit 1" {
  render_with_config "$CFG" "foo/bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not usable"* ]]
}

# ============================================================================
# Argument handling
# ============================================================================

@test "no arguments → usage on stderr, exit 1" {
  render_with_config "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* ]]
}

@test "two arguments → usage on stderr, exit 1" {
  render_with_config "$CFG" 42 extra
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* ]]
}
