#!/usr/bin/env bats
#
# Tests for skills/issue-context/issue-settings.sh — the shared work-item
# settings loader. The loader is sourced, not executed, and sets globals in
# the calling shell, so every test sources it inside a clean subshell via
# `bash -c` and asserts on the globals it prints. Every test points the loader
# at a temp config (via HOME or MY_CLAUDE_SKILLS_CONFIG) so a developer's real
# ~/.my-claude-skills/settings.json can never change a test's outcome.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/issue-settings.sh"

# Expected default values. These must mirror the built-in defaults in
# skills/issue-context/issue-settings.sh.
DEFAULT_VERSION="1"
DEFAULT_SEGMENT="issues"
DEFAULT_TEMPLATE='issues/{id}'
DEFAULT_BRANCH_PATTERNS=(
  '^issues/([0-9]+)[-_]'
  '^issues/([0-9]+)$'
  '^issues/([A-Za-z][A-Za-z0-9]*-[0-9]+)'
  '^issues/(.+)$'
  '^([A-Za-z][A-Za-z0-9]*-[0-9]+)'
)
DEFAULT_URL_PATTERNS=(
  '/issues/([0-9]+)'
  '/browse/([A-Z][A-Z0-9]+-[0-9]+)'
)

# The full pipe-delimited dump line produced by DUMP when every setting is at
# its built-in default.
DEFAULT_OUTPUT="v=$DEFAULT_VERSION|s=$DEFAULT_SEGMENT|t=$DEFAULT_TEMPLATE|b=${DEFAULT_BRANCH_PATTERNS[*]}|u=${DEFAULT_URL_PATTERNS[*]}"

# Source the loader in a subshell and print the resulting globals as one
# pipe-delimited line on stdout. The loader's warnings go to stderr; by
# default that is merged into $output by `run`, so silent tests assert exact
# equality as a guard against stray warnings. Warning-expecting tests pass a
# stderr-sink path as $2 inside the subshell and grep that file instead.
DUMP='
  source "$1" 2>"${2:-/dev/stderr}"
  printf "v=%s|s=%s|t=%s|b=%s|u=%s" \
    "$SETTINGS_VERSION" "$SETTINGS_SEGMENT" "$SETTINGS_BRANCH_TEMPLATE" \
    "${SETTINGS_BRANCH_PATTERNS[*]}" "${SETTINGS_URL_PATTERNS[*]}"
'

# Run the loader with MY_CLAUDE_SKILLS_CONFIG pointing at the given file.
run_with_config() {
  run env MY_CLAUDE_SKILLS_CONFIG="$1" bash -c "$DUMP" _ "$SCRIPT"
}

# Run the loader in the given HOME with no override, asserting no settings
# file exists at the default path inside it. macOS env needs the -u flag
# before the NAME=VALUE assignment.
run_in_isolated_home() {
  local home="$1"
  run env -u MY_CLAUDE_SKILLS_CONFIG HOME="$home" bash -c "$DUMP" _ "$SCRIPT"
}

# ============================================================================
# Defaults
# ============================================================================

@test "no config file and no override → built-in defaults, silent" {
  local home="$TEST_TEMP_DIR/home"
  mkdir -p "$home"
  run_in_isolated_home "$home"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_OUTPUT" ]
}

@test "config with only a present scalar → absent keys fall back to defaults" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{"branchTemplate":"features/{id}"}' > "$cfg"
  run_with_config "$cfg"
  [ "$status" -eq 0 ]
  [ "$output" = "v=$DEFAULT_VERSION|s=$DEFAULT_SEGMENT|t=features/{id}|b=${DEFAULT_BRANCH_PATTERNS[*]}|u=${DEFAULT_URL_PATTERNS[*]}" ]
}

# ============================================================================
# segment key handling
# ============================================================================

@test "non-default segment → honored" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{"segment":"work"}' > "$cfg"
  run_with_config "$cfg"
  [ "$status" -eq 0 ]
  [ "$output" = "${DEFAULT_OUTPUT/s=issues/s=work}" ]
}

@test "explicit empty segment → honored as empty" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{"segment":""}' > "$cfg"
  run_with_config "$cfg"
  [ "$status" -eq 0 ]
  [ "$output" = "${DEFAULT_OUTPUT/|s=issues|/|s=|}" ]
}

@test "non-string segment value → falls back to default" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{"segment":5}' > "$cfg"
  run_with_config "$cfg"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_OUTPUT" ]
}

# ============================================================================
# Malformed config and warnings
# ============================================================================

@test "malformed JSON → warning on stderr, defaults on stdout" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  local err="$TEST_TEMP_DIR/err"
  printf '%s' '{"segment":' > "$cfg"
  run env MY_CLAUDE_SKILLS_CONFIG="$cfg" bash -c "$DUMP" _ "$SCRIPT" "$err"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_OUTPUT" ]
  grep -q "warning" "$err"
  grep -q "$cfg" "$err"
}

@test "override points at missing file → warning on stderr, defaults on stdout" {
  local err="$TEST_TEMP_DIR/err"
  run env MY_CLAUDE_SKILLS_CONFIG="$TEST_TEMP_DIR/does-not-exist.json" \
    bash -c "$DUMP" _ "$SCRIPT" "$err"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_OUTPUT" ]
  grep -q "MY_CLAUDE_SKILLS_CONFIG" "$err"
  grep -q "not readable" "$err"
}

@test "invalid regex in a pattern entry → warning, that key falls back, other keys honored" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  local err="$TEST_TEMP_DIR/err"
  printf '%s' '{"branchPatterns":["^foo/([0-9]+"],"urlPatterns":["/custom/([0-9]+)"]}' > "$cfg"
  run env MY_CLAUDE_SKILLS_CONFIG="$cfg" bash -c "$DUMP" _ "$SCRIPT" "$err"
  [ "$status" -eq 0 ]
  [ "$output" = "v=$DEFAULT_VERSION|s=$DEFAULT_SEGMENT|t=$DEFAULT_TEMPLATE|b=${DEFAULT_BRANCH_PATTERNS[*]}|u=/custom/([0-9]+)" ]
  grep -q "invalid regex" "$err"
  grep -q "branchPatterns" "$err"
}

# ============================================================================
# Env override precedence
# ============================================================================

@test "override wins over a config at the HOME default path" {
  local home="$TEST_TEMP_DIR/home"
  mkdir -p "$home/.my-claude-skills"
  printf '%s' '{"segment":"homeval"}' > "$home/.my-claude-skills/settings.json"
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{"segment":"overrideval"}' > "$cfg"
  run env HOME="$home" MY_CLAUDE_SKILLS_CONFIG="$cfg" bash -c "$DUMP" _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "${DEFAULT_OUTPUT/s=issues/s=overrideval}" ]
}

@test "config at HOME default path read when no override set" {
  local home="$TEST_TEMP_DIR/home"
  mkdir -p "$home/.my-claude-skills"
  printf '%s' '{"segment":"homeval"}' > "$home/.my-claude-skills/settings.json"
  run_in_isolated_home "$home"
  [ "$status" -eq 0 ]
  [ "$output" = "${DEFAULT_OUTPUT/s=issues/s=homeval}" ]
}
