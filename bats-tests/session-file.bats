#!/usr/bin/env bats
#
# Tests for skills/issue-context/session-file.sh — the reader that owns the
# per-session folder-override file. The helper is sourced, not executed, so
# every test sources it inside a clean subshell via `bash -c` and prints the
# outcome as one line, the style bats-tests/issue-settings.bats established.
#
# Every test points MY_CLAUDE_SKILLS_CONFIG at a temp settings file, which puts
# the sessions directory beside it, so a developer's real
# ~/.my-claude-skills/sessions/ can never change a test's outcome.

load test_helper

SETTINGS="$PROJECT_ROOT/skills/issue-context/issue-settings.sh"
SCRIPT="$PROJECT_ROOT/skills/issue-context/session-file.sh"

SESSION_ID="06cb4128-c112-4696-bddb-3a52d1684a20"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
  SESSIONS_DIR="$TEST_TEMP_DIR/sessions"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# Source both helpers and print "<rc>|<folder>|<reason>" for the current
# session. Settings warnings go to a sink so they cannot reach stdout.
READ='
  source "$1" 2>/dev/null
  source "$2"
  folder=""; reason=""
  _issue_context_session_file_read folder reason && rc=0 || rc=1
  printf "%s|%s|%s" "$rc" "$folder" "$reason"
'

read_session() {
  run env MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="${1-$SESSION_ID}" \
    bash -c "$READ" _ "$SETTINGS" "$SCRIPT"
}

# Write a session file with the given basename and body.
write_file() {
  mkdir -p "$SESSIONS_DIR"
  printf '%s' "$2" > "$SESSIONS_DIR/$1"
}

# A well-formed document pointing at <folder>.
valid_doc() {
  cat <<EOF
{
  "version": 1,
  "folder": "$1",
  "session_id": "$SESSION_ID",
  "slug": "my-current-work",
  "written_at": "2026-09-14T18:21:56Z",
  "written_by": { "agent": "claude", "pid": 63294, "child_session": true }
}
EOF
}

# ============================================================================
# Sessions directory resolution
# ============================================================================

@test "sessions dir sits beside the settings file" {
  run env MY_CLAUDE_SKILLS_CONFIG="$CFG" bash -c \
    'source "$1" 2>/dev/null; source "$2"; _issue_context_sessions_dir' \
    _ "$SETTINGS" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/sessions" ]
}

@test "sessions dir follows MY_CLAUDE_SKILLS_CONFIG rather than HOME" {
  local other="$TEST_TEMP_DIR/elsewhere/settings.json"
  mkdir -p "$TEST_TEMP_DIR/elsewhere"
  printf '%s' '{}' > "$other"
  run env HOME="$TEST_TEMP_DIR/home" MY_CLAUDE_SKILLS_CONFIG="$other" bash -c \
    'source "$1" 2>/dev/null; source "$2"; _issue_context_sessions_dir' \
    _ "$SETTINGS" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/elsewhere/sessions" ]
}

# ============================================================================
# The ordinary no-override case
# ============================================================================

@test "no sessions directory → rc 1, reason none" {
  read_session
  [ "$status" -eq 0 ]
  [ "$output" = "1||none" ]
}

@test "sessions directory with no file for this session → rc 1, reason none" {
  write_file "other-session.json" "$(valid_doc "$TEST_TEMP_DIR")"
  read_session
  [ "$output" = "1||none" ]
}

@test "no session id → rc 1, reason none" {
  write_file "${SESSION_ID}.json" "$(valid_doc "$TEST_TEMP_DIR")"
  # -u, not merely omitted: a bats run started from a Claude Code session
  # inherits a real CLAUDE_CODE_SESSION_ID, and this test is about its absence.
  run env -u CLAUDE_CODE_SESSION_ID MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c "$READ" _ "$SETTINGS" "$SCRIPT"
  [ "$output" = "1||none" ]
}

# ============================================================================
# A valid file
# ============================================================================

@test "valid file with a slug → rc 0, folder returned" {
  write_file "${SESSION_ID}--my-current-work.json" "$(valid_doc "$TEST_TEMP_DIR/topic")"
  read_session
  [ "$output" = "0|$TEST_TEMP_DIR/topic|" ]
}

@test "valid file with no slug → rc 0, folder returned" {
  write_file "${SESSION_ID}.json" "$(valid_doc "$TEST_TEMP_DIR/topic")"
  read_session
  [ "$output" = "0|$TEST_TEMP_DIR/topic|" ]
}

@test "unrecognised fields are ignored rather than refused" {
  write_file "${SESSION_ID}.json" \
    "{\"version\":1,\"folder\":\"$TEST_TEMP_DIR/topic\",\"future_key\":[1,2,3]}"
  read_session
  [ "$output" = "0|$TEST_TEMP_DIR/topic|" ]
}

@test "the folder is returned verbatim, not resolved or checked" {
  # Existence and containment are the resolver's job, not the reader's.
  write_file "${SESSION_ID}.json" \
    "{\"version\":1,\"folder\":\"/nowhere/at/all\"}"
  read_session
  [ "$output" = "0|/nowhere/at/all|" ]
}

# ============================================================================
# Refusals
# ============================================================================

@test "two files for one session → rc 1, reason duplicate" {
  write_file "${SESSION_ID}.json" "$(valid_doc "$TEST_TEMP_DIR/one")"
  write_file "${SESSION_ID}--later.json" "$(valid_doc "$TEST_TEMP_DIR/two")"
  read_session
  [ "$output" = "1||duplicate" ]
}

# ============================================================================
# Only the two documented filename forms match
# ============================================================================

@test "a file whose id merely starts with this session's id is ignored" {
  write_file "${SESSION_ID}-other.json" "$(valid_doc "$TEST_TEMP_DIR/stranger")"
  read_session
  [ "$output" = "1||none" ]
}

@test "a prefix collision does not turn a valid override into a duplicate" {
  # The stranger's id starts with this session's and continues with a single
  # dash, so it is not the <id>--<slug> form and must not be read here. An
  # <id>* glob would match it, and the valid file beside it would be discarded
  # as a duplicate rather than returned.
  write_file "${SESSION_ID}.json" "$(valid_doc "$TEST_TEMP_DIR/mine")"
  write_file "${SESSION_ID}-other.json" "$(valid_doc "$TEST_TEMP_DIR/stranger")"
  read_session
  [ "$output" = "0|$TEST_TEMP_DIR/mine|" ]
}

@test "a prefix collision is not read even when this session owns a slug file" {
  write_file "${SESSION_ID}--mine.json" "$(valid_doc "$TEST_TEMP_DIR/mine")"
  write_file "${SESSION_ID}-other--mine.json" "$(valid_doc "$TEST_TEMP_DIR/stranger")"
  read_session
  [ "$output" = "0|$TEST_TEMP_DIR/mine|" ]
}

@test "malformed JSON → rc 1, reason malformed" {
  write_file "${SESSION_ID}.json" '{"version":1,"folder":'
  read_session
  [ "$output" = "1||malformed" ]
}

@test "JSON that is not an object → rc 1, reason malformed" {
  write_file "${SESSION_ID}.json" '["version",1]'
  read_session
  [ "$output" = "1||malformed" ]
}

@test "missing folder field → rc 1, reason malformed" {
  write_file "${SESSION_ID}.json" '{"version":1}'
  read_session
  [ "$output" = "1||malformed" ]
}

@test "empty folder field → rc 1, reason malformed" {
  write_file "${SESSION_ID}.json" '{"version":1,"folder":""}'
  read_session
  [ "$output" = "1||malformed" ]
}

@test "non-string folder field → rc 1, reason malformed" {
  write_file "${SESSION_ID}.json" '{"version":1,"folder":42}'
  read_session
  [ "$output" = "1||malformed" ]
}

@test "unknown version → rc 1, reason version" {
  write_file "${SESSION_ID}.json" \
    "{\"version\":2,\"folder\":\"$TEST_TEMP_DIR/topic\"}"
  read_session
  [ "$output" = "1||version" ]
}

@test "missing version → rc 1, reason malformed" {
  write_file "${SESSION_ID}.json" \
    "{\"folder\":\"$TEST_TEMP_DIR/topic\"}"
  read_session
  [ "$output" = "1||malformed" ]
}

@test "string version is not accepted as the number it looks like" {
  write_file "${SESSION_ID}.json" \
    "{\"version\":\"1\",\"folder\":\"$TEST_TEMP_DIR/topic\"}"
  read_session
  [ "$output" = "1||malformed" ]
}

@test "unreadable file → rc 1, reason malformed" {
  write_file "${SESSION_ID}.json" "$(valid_doc "$TEST_TEMP_DIR/topic")"
  chmod a-r "$SESSIONS_DIR/${SESSION_ID}.json"
  read_session
  chmod u+r "$SESSIONS_DIR/${SESSION_ID}.json"
  [ "$output" = "1||malformed" ]
}

@test "jq absent → rc 1, reason nojq" {
  write_file "${SESSION_ID}.json" "$(valid_doc "$TEST_TEMP_DIR/topic")"
  # An empty PATH, not a trimmed one: jq is at /usr/bin/jq on this machine, so
  # pointing PATH at the system directories would leave it found and test
  # nothing. The reader resolves the sessions directory with parameter
  # expansion rather than dirname precisely so it still works here.
  # /bin/bash by absolute path: with PATH emptied, env cannot look `bash` up.
  run env PATH="" MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    /bin/bash -c "$READ" _ "$SETTINGS" "$SCRIPT"
  [ "$output" = "1||nojq" ]
}

# ============================================================================
# The reader never exits and never prints
# ============================================================================

@test "reading is silent on every failure path" {
  write_file "${SESSION_ID}.json" '{"version":1,"folder":'
  run env MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    bash -c 'source "$1" 2>/dev/null; source "$2"
             f=""; r=""
             _issue_context_session_file_read f r || true' \
    _ "$SETTINGS" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
