#!/usr/bin/env bats
#
# Tests for skills/issue-context/session-hook-state.sh — whether the session
# hook runs at UserPromptSubmit, and through which install. Each test points
# SESSION_HOOK_STATE_SETTINGS or CLAUDE_CONFIG_DIR at a temp file, so the
# settings of a developer never change an outcome.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/session-hook-state.sh"

setup() {
  TEST_TEMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  SETTINGS="$TEST_TEMP_DIR/settings.json"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# run_state [args...] — run the script with SETTINGS as its settings file.
run_state() {
  run --separate-stderr env -u CLAUDE_CONFIG_DIR SESSION_HOOK_STATE_SETTINGS="$SETTINGS" \
    SESSION_HOOK_STATE_MANAGED="$TEST_TEMP_DIR/no-managed.json" "$SCRIPT" "$@"
}

@test "session-hook-state: a UserPromptSubmit entry of the hook gives settings" {
  printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/x/skills/issue-context/session-hook.sh"}]}]}}' > "$SETTINGS"
  run_state
  [ "$status" -eq 0 ]
  [ "$output" = "settings" ]
}

@test "session-hook-state: an entry of the hook under another event only gives none" {
  printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/x/skills/issue-context/session-hook.sh"}]}]}}' > "$SETTINGS"
  run_state
  [ "$output" = "none" ]
}

@test "session-hook-state: an enabled my-claude-skills plugin gives none, a documented limit" {
  printf '{"enabledPlugins":{"other@x":true,"my-claude-skills@my-claude-skills":true}}' > "$SETTINGS"
  run_state
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "session-hook-state: a missing file, a file that is not JSON, and a JSON array give none" {
  run_state
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
  printf 'not json' > "$SETTINGS"
  run_state
  [ "$output" = "none" ]
  printf '[]' > "$SETTINGS"
  run_state
  [ "$output" = "none" ]
}

@test "session-hook-state: with no override, the file comes from CLAUDE_CONFIG_DIR" {
  mkdir -p "$TEST_TEMP_DIR/config"
  printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/x/skills/issue-context/session-hook.sh"}]}]}}' > "$TEST_TEMP_DIR/config/settings.json"
  run --separate-stderr env -u SESSION_HOOK_STATE_SETTINGS CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/config" \
    SESSION_HOOK_STATE_MANAGED="$TEST_TEMP_DIR/no-managed.json" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "settings" ]
}

@test "session-hook-state: --help prints the header and exits 0" {
  run_state --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"session-hook-state.sh"* ]] || false
}

@test "session-hook-state: an unknown argument → exit 1, K001" {
  run_state --nope
  [ "$status" -eq 1 ]
  [[ "$stderr" == *K001* ]] || false
}

@test "session-hook-state: no jq on PATH → exit 1, K002" {
  # The shared helper keeps each tool of PATH but jq, as the jq-missing tests
  # of session-hook.bats and folder-sessions.bats do. A PATH with only a few
  # tools broke the kcov tracer of the child bash on macOS (2026-11-04).
  local nojq
  nojq="$(_stub_path_without "$TEST_TEMP_DIR/nojq" jq)"
  run --separate-stderr env -u CLAUDE_CONFIG_DIR PATH="$nojq" SESSION_HOOK_STATE_SETTINGS="$SETTINGS" \
    SESSION_HOOK_STATE_MANAGED="$TEST_TEMP_DIR/no-managed.json" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *K002* ]] || false
}

# ============================================================================
# disableAllHooks (CodeRabbit review of PR 313)
# ============================================================================

# hook_entry — a user settings file whose UserPromptSubmit entry runs the hook,
# with the extra top-level keys given as JSON members.
hook_entry() {
  printf '{%s"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/x/skills/issue-context/session-hook.sh"}]}]}}' "${1:+$1,}" > "$SETTINGS"
}

# project_file <name> <json> — write <dir>/.claude/<name> of the project.
project_file() {
  mkdir -p "$TEST_TEMP_DIR/project/.claude"
  printf '%s' "$2" > "$TEST_TEMP_DIR/project/.claude/$1"
}

@test "session-hook-state: disableAllHooks true in the user settings gives none" {
  hook_entry '"disableAllHooks":true'
  run_state
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "session-hook-state: disableAllHooks true in the project settings gives none" {
  hook_entry
  project_file settings.json '{"disableAllHooks":true}'
  run_state --project "$TEST_TEMP_DIR/project"
  [ "$output" = "none" ]
  run_state
  [ "$output" = "settings" ]
}

@test "session-hook-state: the local settings override the project settings" {
  hook_entry
  project_file settings.json '{"disableAllHooks":true}'
  project_file settings.local.json '{"disableAllHooks":false}'
  run_state --project "$TEST_TEMP_DIR/project"
  [ "$output" = "settings" ]
}

@test "session-hook-state: a project file that is not JSON changes nothing" {
  hook_entry '"disableAllHooks":true'
  project_file settings.json 'not json'
  run_state --project "$TEST_TEMP_DIR/project"
  [ "$output" = "none" ]
}

@test "session-hook-state: --project with no directory → exit 1, K001" {
  run_state --project
  [ "$status" -eq 1 ]
  [[ "$stderr" == *K001* ]] || false
}

# ============================================================================
# The contract of strong evidence (PR 313, review 5774396690)
# ============================================================================

@test "session-hook-state: a hook entry only in the project file gives none, a documented limit" {
  printf '{}' > "$SETTINGS"
  project_file settings.json '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/x/skills/issue-context/session-hook.sh"}]}]}}'
  run_state --project "$TEST_TEMP_DIR/project"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "session-hook-state: a managed settings file gives none, with the hook entry in the user file" {
  hook_entry
  printf '{}' > "$TEST_TEMP_DIR/managed.json"
  run --separate-stderr env -u CLAUDE_CONFIG_DIR SESSION_HOOK_STATE_SETTINGS="$SETTINGS" \
    SESSION_HOOK_STATE_MANAGED="$TEST_TEMP_DIR/managed.json" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "session-hook-state: a managed settings file that is not JSON also gives none" {
  hook_entry
  printf 'not json' > "$TEST_TEMP_DIR/managed.json"
  run --separate-stderr env -u CLAUDE_CONFIG_DIR SESSION_HOOK_STATE_SETTINGS="$SETTINGS" \
    SESSION_HOOK_STATE_MANAGED="$TEST_TEMP_DIR/managed.json" "$SCRIPT"
  [ "$output" = "none" ]
}
