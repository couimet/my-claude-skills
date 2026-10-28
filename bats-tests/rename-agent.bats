#!/usr/bin/env bats
#
# Tests for skills/issue-context/rename-agent.sh — the record of the name
# that the current session asks for. The session hook applies it at the next
# prompt; session-hook.bats tests that half.
#
# The sessions directory and the title records sit beside a temp settings
# file, so a developer's real sessions never change an outcome. `claude` is a
# stub that logs each call, so a test can check that the script runs none.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/rename-agent.sh"

SELF_SESSION="cfc8ea00-2d7e-4433-8674-ca4967af007a"

setup() {
  TEST_TEMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  BIN="$TEST_TEMP_DIR/bin"
  mkdir -p "$BIN"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$TEST_TEMP_DIR/calls.txt" > "$BIN/claude"
  chmod +x "$BIN/claude"
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
  SESSIONS_DIR="$TEST_TEMP_DIR/sessions"
  TITLES_DIR="$TEST_TEMP_DIR/session-titles"
  mkdir -p "$SESSIONS_DIR" "$TEST_TEMP_DIR/my-topic"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# session_file <session-id> <folder> — write a session file the way
# set-work-folder.sh does.
session_file() {
  printf '{"version":1,"folder":"%s","session_id":"%s","job_session_id":null,"written_at":"2026-10-13T10:00:00Z"}' \
    "$2" "$1" > "$SESSIONS_DIR/$1--t.json"
}

# run_rename [self-session] <args...> — run the script in a clean environment.
run_rename() {
  local self="$1"
  shift
  run --separate-stderr env -u CLAUDE_JOB_DIR -u CLAUDE_PID -u CLAUDE_CODE_SESSION_ID \
    ${self:+CLAUDE_CODE_SESSION_ID="$self"} \
    PATH="$BIN:$PATH" MY_CLAUDE_SKILLS_CONFIG="$CFG" "$SCRIPT" "$@"
}

@test "rename-agent: no argument asks for the folder name of the bound folder" {
  session_file "$SELF_SESSION" "$TEST_TEMP_DIR/my-topic"
  run_rename "$SELF_SESSION"
  [ "$status" -eq 0 ]
  [ "$output" = "The name my-topic applies at your next prompt." ]
  [ "$(jq -r .wanted "$TITLES_DIR/$SELF_SESSION.json")" = "my-topic" ]
}

@test "rename-agent: an argument asks for that name" {
  session_file "$SELF_SESSION" "$TEST_TEMP_DIR/my-topic"
  run_rename "$SELF_SESSION" my own name
  [ "$status" -eq 0 ]
  [ "$output" = "The name my own name applies at your next prompt." ]
  [ "$(jq -r .wanted "$TITLES_DIR/$SELF_SESSION.json")" = "my own name" ]
}

@test "rename-agent: an argument works in a session with no session file" {
  run_rename "$SELF_SESSION" chosen-name
  [ "$status" -eq 0 ]
  [ "$(jq -r .wanted "$TITLES_DIR/$SELF_SESSION.json")" = "chosen-name" ]
}

@test "rename-agent: no argument and no session file renames nothing and names the fix" {
  run_rename "$SELF_SESSION"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"N003"*"/launch-agent"*"/set-work-folder"* ]] || false
  [ ! -e "$TITLES_DIR" ]
}

@test "rename-agent: the record keeps the other fields of the hook" {
  session_file "$SELF_SESSION" "$TEST_TEMP_DIR/my-topic"
  mkdir -p "$TITLES_DIR"
  printf '{"set":"old","warned":"x"}' > "$TITLES_DIR/$SELF_SESSION.json"
  run_rename "$SELF_SESSION"
  [ "$status" -eq 0 ]
  [ "$(jq -c . "$TITLES_DIR/$SELF_SESSION.json")" = '{"set":"old","warned":"x","wanted":"my-topic"}' ]
}

@test "rename-agent: a record that is not a JSON object is replaced" {
  mkdir -p "$TITLES_DIR"
  printf 'not json' > "$TITLES_DIR/$SELF_SESSION.json"
  run_rename "$SELF_SESSION" chosen-name
  [ "$status" -eq 0 ]
  [ "$(jq -c . "$TITLES_DIR/$SELF_SESSION.json")" = '{"wanted":"chosen-name"}' ]
}

@test "rename-agent: it writes only the record of the current session, and runs no claude command" {
  run_rename "$SELF_SESSION" chosen-name
  [ "$status" -eq 0 ]
  [ "$(ls "$TITLES_DIR")" = "$SELF_SESSION.json" ]
  [ ! -e "$TEST_TEMP_DIR/calls.txt" ]
}

@test "rename-agent: no session id gives N002" {
  run_rename "" chosen-name
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"N002"* ]] || false
}

@test "rename-agent: a name with a newline gives N001" {
  run_rename "$SELF_SESSION" "two
lines"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"N001"* ]] || false
  [ ! -e "$TITLES_DIR" ]
}

@test "rename-agent: an unknown flag gives N001, and --help exits 0" {
  run_rename "$SELF_SESSION" --nope
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"N001"* ]] || false
  run_rename "$SELF_SESSION" --help
  [ "$status" -eq 0 ]
  [[ "$output" == "Usage: rename-agent.sh"* ]] || false
}
