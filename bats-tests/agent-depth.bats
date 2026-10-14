#!/usr/bin/env bats
#
# Tests for skills/issue-context/agent-depth.sh — the record of how deep in a
# chain of agents a session sits. The helper is sourced, not executed, so every
# test sources it with issue-settings.sh inside a clean subshell, with
# MY_CLAUDE_SKILLS_CONFIG in the temp directory so the records land there.

load test_helper

HELPERS="$PROJECT_ROOT/skills/issue-context"
SESSION_ID="5e0a9b12-7c3d-4e8f-a1b2-c3d4e5f60718"

setup() {
  TEST_TEMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
  DEPTH_DIR="$TEST_TEMP_DIR/agent-depth"
}

# depth_read [session-id] — print "<rc>|<depth>" for the given session, or for
# a plain shell when no id is given.
depth_read() {
  run env -u CLAUDE_CODE_SESSION_ID MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    ${1:+CLAUDE_CODE_SESSION_ID="$1"} bash -c '
    source "$1/issue-settings.sh" 2>/dev/null && source "$1/agent-depth.sh"
    d=x; _issue_context_agent_depth_read d && rc=0 || rc=$?
    printf "%s|%s\n" "$rc" "$d"' _ "$HELPERS"
}

# depth_write <key> <depth> — print the return code of a write.
depth_write() {
  run env MY_CLAUDE_SKILLS_CONFIG="$CFG" bash -c '
    source "$1/issue-settings.sh" 2>/dev/null && source "$1/agent-depth.sh"
    _issue_context_agent_depth_write "$2" "$3" && echo 0 || echo $?' _ "$HELPERS" "$1" "$2"
}

@test "a plain shell is depth 0" {
  depth_read
  [ "$output" = "0|0" ]
}

@test "a session with no record is depth 0" {
  depth_read "$SESSION_ID"
  [ "$output" = "0|0" ]
}

@test "a written record is read back by the first 8 characters of the session id" {
  depth_write "${SESSION_ID:0:8}" 2
  [ "$output" = "0" ]
  [ "$(cat "$DEPTH_DIR/${SESSION_ID:0:8}")" = "2" ]
  depth_read "$SESSION_ID"
  [ "$output" = "0|2" ]
}

@test "a leading zero reads as decimal, not octal" {
  mkdir -p "$DEPTH_DIR"
  printf '09\n' > "$DEPTH_DIR/${SESSION_ID:0:8}"
  depth_read "$SESSION_ID"
  [ "$output" = "0|9" ]
}

@test "a record that is not an integer refuses" {
  mkdir -p "$DEPTH_DIR"
  printf 'two\n' > "$DEPTH_DIR/${SESSION_ID:0:8}"
  depth_read "$SESSION_ID"
  [ "${output%%|*}" = "1" ]
}

@test "a record of more than nine digits refuses, so it cannot overflow" {
  mkdir -p "$DEPTH_DIR"
  printf '18446744073709551617\n' > "$DEPTH_DIR/${SESSION_ID:0:8}"
  depth_read "$SESSION_ID"
  [ "${output%%|*}" = "1" ]
}

@test "a record that is a directory refuses" {
  mkdir -p "$DEPTH_DIR/${SESSION_ID:0:8}"
  depth_read "$SESSION_ID"
  [ "${output%%|*}" = "1" ]
}

@test "a session id that cannot name a file refuses" {
  depth_read "../../x-yz"
  [ "${output%%|*}" = "1" ]
}

@test "a write refuses a key with a slash and a depth that is not an integer" {
  depth_write "../a" 1
  [ "$output" = "1" ]
  depth_write "abcd1234" "-1"
  [ "$output" = "1" ]
  depth_write "abcd1234" "1000000000"
  [ "$output" = "1" ]
  [ ! -e "$DEPTH_DIR/abcd1234" ]
}

@test "a second write replaces the first and leaves no temporary file" {
  depth_write abcd1234 1
  depth_write abcd1234 2
  [ "$(cat "$DEPTH_DIR/abcd1234")" = "2" ]
  [ "$(ls -A "$DEPTH_DIR")" = "abcd1234" ]
}

@test "a settings file name with no directory puts the records under ./agent-depth" {
  run bash -c 'cd "$2" && source "$1/agent-depth.sh" && SETTINGS_FILE=settings.json _issue_context_agent_depth_dir' \
    _ "$HELPERS" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "./agent-depth" ]
}

@test "a write whose rename fails returns 1 and removes its temporary file" {
  run env MY_CLAUDE_SKILLS_CONFIG="$CFG" bash -c '
    source "$1/issue-settings.sh" 2>/dev/null && source "$1/agent-depth.sh"
    mv() { return 1; }
    _issue_context_agent_depth_write abcd1234 1 && echo 0 || echo $?' _ "$HELPERS"
  [ "$output" = "1" ]
  [ ! -e "$DEPTH_DIR/abcd1234" ]
  [ -z "$(ls -A "$DEPTH_DIR")" ]
}
