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
DEFAULT_IDENTIFIER_CASE="upper"
DEFAULT_BRANCH_PATTERNS=(
  '^issues/([0-9]+)[-_]'
  '^issues/([0-9]+)$'
  '^issues/([A-Za-z][A-Za-z0-9]*-[0-9]+)'
  '^issues/(.+)$'
  '^([A-Za-z][A-Za-z0-9]*-[0-9]+)'
)
DEFAULT_URL_PATTERNS=(
  '/issues/([0-9]+)'
  '/browse/([A-Za-z][A-Za-z0-9]+-[0-9]+)'
)

# The full pipe-delimited dump line produced by DUMP when every setting is at
# its built-in default.
DEFAULT_OUTPUT="v=$DEFAULT_VERSION|s=$DEFAULT_SEGMENT|t=$DEFAULT_TEMPLATE|b=${DEFAULT_BRANCH_PATTERNS[*]}|u=${DEFAULT_URL_PATTERNS[*]}|c=$DEFAULT_IDENTIFIER_CASE"

# Source the loader in a subshell and print the resulting globals as one
# pipe-delimited line on stdout. The loader's warnings go to stderr; by
# default that is merged into $output by `run`, so silent tests assert exact
# equality as a guard against stray warnings. Warning-expecting tests pass a
# stderr-sink path as $2 inside the subshell and grep that file instead.
DUMP='
  source "$1" 2>"${2:-/dev/stderr}"
  printf "v=%s|s=%s|t=%s|b=%s|u=%s|c=%s" \
    "$SETTINGS_VERSION" "$SETTINGS_SEGMENT" "$SETTINGS_BRANCH_TEMPLATE" \
    "${SETTINGS_BRANCH_PATTERNS[*]}" "${SETTINGS_URL_PATTERNS[*]}" \
    "$SETTINGS_IDENTIFIER_CASE"
'

# Source the loader in a subshell and print what the shared normalizer makes of
# a value, so the fold can be asserted without going through a resolver.
NORMALIZE='
  source "$1" 2>/dev/null
  _issue_settings_normalize_identifier "$2"
'

# Normalize the given value under the given config file.
run_normalize() {
  run env MY_CLAUDE_SKILLS_CONFIG="$1" bash -c "$NORMALIZE" _ "$SCRIPT" "$2"
}

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
  [ "$output" = "v=$DEFAULT_VERSION|s=$DEFAULT_SEGMENT|t=features/{id}|b=${DEFAULT_BRANCH_PATTERNS[*]}|u=${DEFAULT_URL_PATTERNS[*]}|c=$DEFAULT_IDENTIFIER_CASE" ]
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

@test "unsafe segment with slash traversal → falls back to default with warning" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  local err="$TEST_TEMP_DIR/err"
  printf '%s' '{"segment":"work/../x"}' > "$cfg"
  run env MY_CLAUDE_SKILLS_CONFIG="$cfg" bash -c "$DUMP" _ "$SCRIPT" "$err"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_OUTPUT" ]
  grep -q "invalid segment 'work/../x'" "$err"
  grep -q "using default segment 'issues'" "$err"
}

@test "unsafe dotdot segment → falls back to default with warning" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  local err="$TEST_TEMP_DIR/err"
  printf '%s' '{"segment":".."}' > "$cfg"
  run env MY_CLAUDE_SKILLS_CONFIG="$cfg" bash -c "$DUMP" _ "$SCRIPT" "$err"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_OUTPUT" ]
  grep -q "invalid segment '..'" "$err"
}

@test "unsafe segment with leading dot → falls back to default with warning" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  local err="$TEST_TEMP_DIR/err"
  printf '%s' '{"segment":".hidden"}' > "$cfg"
  run env MY_CLAUDE_SKILLS_CONFIG="$cfg" bash -c "$DUMP" _ "$SCRIPT" "$err"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_OUTPUT" ]
  grep -q "invalid segment '.hidden'" "$err"
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
  [ "$output" = "v=$DEFAULT_VERSION|s=$DEFAULT_SEGMENT|t=$DEFAULT_TEMPLATE|b=${DEFAULT_BRANCH_PATTERNS[*]}|u=/custom/([0-9]+)|c=$DEFAULT_IDENTIFIER_CASE" ]
  grep -q "invalid regex" "$err"
  grep -q "branchPatterns" "$err"
}

@test "non-string member in a pattern array → warning, that key falls back, other keys honored" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  local err="$TEST_TEMP_DIR/err"
  # A numeric member would otherwise be coerced to "42" by jq -r and pass the
  # regex check as one wrong pattern; it must fall the whole key back instead.
  printf '%s' '{"branchPatterns":["^issues/([0-9]+)$",42],"segment":"work"}' > "$cfg"
  run env MY_CLAUDE_SKILLS_CONFIG="$cfg" bash -c "$DUMP" _ "$SCRIPT" "$err"
  [ "$status" -eq 0 ]
  [ "$output" = "v=$DEFAULT_VERSION|s=work|t=$DEFAULT_TEMPLATE|b=${DEFAULT_BRANCH_PATTERNS[*]}|u=${DEFAULT_URL_PATTERNS[*]}|c=$DEFAULT_IDENTIFIER_CASE" ]
  grep -q "non-string entry" "$err"
  grep -q "branchPatterns" "$err"
}

@test "boolean member in a pattern array → warning, that key falls back" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  local err="$TEST_TEMP_DIR/err"
  printf '%s' '{"urlPatterns":["/issues/([0-9]+)",true]}' > "$cfg"
  run env MY_CLAUDE_SKILLS_CONFIG="$cfg" bash -c "$DUMP" _ "$SCRIPT" "$err"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_OUTPUT" ]
  grep -q "non-string entry" "$err"
  grep -q "urlPatterns" "$err"
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

# ============================================================================
# identifierCase key handling
# ============================================================================

@test "absent identifierCase → defaults to upper" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$cfg"
  run_with_config "$cfg"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_OUTPUT" ]
}

@test "identifierCase lower → honored" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{"identifierCase":"lower"}' > "$cfg"
  run_with_config "$cfg"
  [ "$status" -eq 0 ]
  [ "$output" = "${DEFAULT_OUTPUT/c=upper/c=lower}" ]
}

@test "identifierCase preserve → honored" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{"identifierCase":"preserve"}' > "$cfg"
  run_with_config "$cfg"
  [ "$status" -eq 0 ]
  [ "$output" = "${DEFAULT_OUTPUT/c=upper/c=preserve}" ]
}

@test "unknown identifierCase → falls back to upper with warning" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  local err="$TEST_TEMP_DIR/err"
  printf '%s' '{"identifierCase":"Upper"}' > "$cfg"
  run env MY_CLAUDE_SKILLS_CONFIG="$cfg" bash -c "$DUMP" _ "$SCRIPT" "$err"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_OUTPUT" ]
  grep -q "invalid identifierCase 'Upper'" "$err"
  grep -q "using default identifierCase 'upper'" "$err"
}

@test "non-string identifierCase → falls back to upper" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{"identifierCase":5}' > "$cfg"
  run_with_config "$cfg"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_OUTPUT" ]
}

# ============================================================================
# The shared identifier normalizer
# ============================================================================

@test "normalizer folds a key-shaped identifier to upper by default" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$cfg"
  run_normalize "$cfg" "proj-1234"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-1234" ]
}

@test "normalizer folds a mixed-case key-shaped identifier" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$cfg"
  run_normalize "$cfg" "Proj-1234"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-1234" ]
}

@test "normalizer folds to lower when configured" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{"identifierCase":"lower"}' > "$cfg"
  run_normalize "$cfg" "PROJ-1234"
  [ "$status" -eq 0 ]
  [ "$output" = "proj-1234" ]
}

@test "normalizer leaves everything alone under preserve" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{"identifierCase":"preserve"}' > "$cfg"
  run_normalize "$cfg" "proj-1234"
  [ "$status" -eq 0 ]
  [ "$output" = "proj-1234" ]
}

@test "normalizer leaves a numeric identifier alone" {
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$cfg"
  run_normalize "$cfg" "262"
  [ "$status" -eq 0 ]
  [ "$output" = "262" ]
}

@test "normalizer leaves a free-form slug alone" {
  # The shape guard is the whole reason a blanket fold was rejected: without it
  # the branchPatterns catch-all would turn issues/my-feature into MY-FEATURE.
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$cfg"
  run_normalize "$cfg" "my-feature"
  [ "$status" -eq 0 ]
  [ "$output" = "my-feature" ]
}

@test "normalizer folds a slug that happens to be key-shaped" {
  # Documented collateral of the shape guard: release-2 is indistinguishable
  # from a tracker key, so it folds. identifierCase preserve is the escape.
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$cfg"
  run_normalize "$cfg" "release-2"
  [ "$status" -eq 0 ]
  [ "$output" = "RELEASE-2" ]
}

@test "empty identifierCase → falls back to upper, silently" {
  # An empty value expresses nothing, so it takes the default without a
  # warning. Warning here would also turn any transient empty read of the key
  # into a stderr line that callers asserting on clean output would trip over.
  local cfg="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{"identifierCase":""}' > "$cfg"
  run_with_config "$cfg"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_OUTPUT" ]
}
