#!/usr/bin/env bats
#
# Tests for skills/issue-context/tier-folders.sh: one line per tier that
# resolves, in tier order, with the winner first.
#
# Every test points MY_CLAUDE_SKILLS_CONFIG at a temp settings file and works
# in a temp git repository, so a developer's real sessions directory and real
# checkouts can never change an outcome.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/tier-folders.sh"
RESOLVER="$PROJECT_ROOT/skills/issue-context/get-issue-folder-path.sh"
SESSION_ID="06cb4128-c112-4696-bddb-3a52d1684a20"
TAB="$(printf '\t')"

# Every CLAUDE_* variable the scripts read is unset first: a bats run started
# from a Claude Code session inherits a real session id.
CLAUDE_ENV_RESET=(env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_JOB_DIR \
  -u CLAUDE_CODE_AGENT -u CLAUDE_PID -u CLAUDE_CODE_CHILD_SESSION)

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  cd "$TEST_TEMP_DIR"
  git init -q .
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  git checkout -q -B issues/42
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
  SESSIONS_DIR="$TEST_TEMP_DIR/sessions"
  TOPIC="$TEST_TEMP_DIR/topic"
  SESSION_TOPIC="$TEST_TEMP_DIR/session-topic"
  mkdir -p "$TOPIC" "$SESSION_TOPIC"
  BRANCH_FOLDER="$TEST_TEMP_DIR/.claude-work/issues/42"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

folders() {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$SCRIPT" "$@"
}

write_marker() {
  printf '%s\n' "$1" > "$TEST_TEMP_DIR/CLAUDE_WORK_FOLDER"
}

write_session_file() {
  mkdir -p "$SESSIONS_DIR"
  printf '{"version":1,"folder":"%s","session_id":"%s"}' \
    "$1" "$SESSION_ID" > "$SESSIONS_DIR/${SESSION_ID}.json"
}

@test "nothing set: the branch line alone" {
  folders
  [ "$status" -eq 0 ]
  [ "$output" = "branch${TAB}$BRANCH_FOLDER" ]
}

@test "a branch matching no pattern: the branch line is the bare root" {
  git checkout -q -B main
  folders
  [ "$status" -eq 0 ]
  [ "$output" = "branch${TAB}$TEST_TEMP_DIR/.claude-work" ]
}

@test "a marker: the worktree line wins, and the branch line follows" {
  write_marker "$TOPIC"
  folders
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "worktree${TAB}$TOPIC" ]
  [ "${lines[1]}" = "branch${TAB}$BRANCH_FOLDER" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "a session override and a marker: all three lines, session first" {
  write_marker "$TOPIC"
  write_session_file "$SESSION_TOPIC"
  folders
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "session${TAB}$SESSION_TOPIC" ]
  [ "${lines[1]}" = "worktree${TAB}$TOPIC" ]
  [ "${lines[2]}" = "branch${TAB}$BRANCH_FOLDER" ]
}

@test "--no-session leaves the session line out" {
  write_marker "$TOPIC"
  write_session_file "$SESSION_TOPIC"
  folders --no-session
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "worktree${TAB}$TOPIC" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "a marker naming a folder that is gone prints no worktree line" {
  write_marker "$TEST_TEMP_DIR/gone"
  folders
  [ "$status" -eq 0 ]
  [ "$output" = "branch${TAB}$BRANCH_FOLDER" ]
}

@test "a session file naming a folder that is gone prints no session line" {
  write_session_file "$TEST_TEMP_DIR/gone"
  folders
  [ "$status" -eq 0 ]
  [ "$output" = "branch${TAB}$BRANCH_FOLDER" ]
}

@test "a malformed session file prints no session line" {
  mkdir -p "$SESSIONS_DIR"
  printf 'not json' > "$SESSIONS_DIR/${SESSION_ID}.json"
  write_marker "$TOPIC"
  folders
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "worktree${TAB}$TOPIC" ]
}

@test "nothing is printed on stderr" {
  write_marker "$TEST_TEMP_DIR/gone"
  folders
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "the first line is the folder the resolver prints" {
  local combo
  for combo in none marker both; do
    rm -f "$TEST_TEMP_DIR/CLAUDE_WORK_FOLDER" "$SESSIONS_DIR/${SESSION_ID}.json"
    case "$combo" in
      marker) write_marker "$TOPIC" ;;
      both) write_marker "$TOPIC"; write_session_file "$SESSION_TOPIC" ;;
    esac
    folders
    local first="${lines[0]#*"$TAB"}"
    run --separate-stderr "${CLAUDE_ENV_RESET[@]}" CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
      MY_CLAUDE_SKILLS_CONFIG="$CFG" "$RESOLVER"
    [ "$output" = "$first" ]
  done
}

@test "an unknown argument is a usage error" {
  folders --bogus
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *usage* ]]
}
