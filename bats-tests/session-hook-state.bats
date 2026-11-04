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
  run --separate-stderr env -u CLAUDE_CONFIG_DIR SESSION_HOOK_STATE_SETTINGS="$SETTINGS" "$SCRIPT" "$@"
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

@test "session-hook-state: an enabled my-claude-skills plugin gives plugin" {
  printf '{"enabledPlugins":{"other@x":true,"my-claude-skills@my-claude-skills":true}}' > "$SETTINGS"
  run_state
  [ "$status" -eq 0 ]
  [ "$output" = "plugin" ]
}

@test "session-hook-state: a disabled my-claude-skills plugin gives none" {
  printf '{"enabledPlugins":{"my-claude-skills@my-claude-skills":false}}' > "$SETTINGS"
  run_state
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
  printf '{"enabledPlugins":{"my-claude-skills@m":true}}' > "$TEST_TEMP_DIR/config/settings.json"
  run --separate-stderr env -u SESSION_HOOK_STATE_SETTINGS CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/config" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "plugin" ]
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
  local bin="$TEST_TEMP_DIR/bin"
  mkdir -p "$bin"
  local tool
  for tool in bash dirname cat; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  run --separate-stderr env -u CLAUDE_CONFIG_DIR PATH="$bin" SESSION_HOOK_STATE_SETTINGS="$SETTINGS" "$bin/bash" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *K002* ]] || false
}
