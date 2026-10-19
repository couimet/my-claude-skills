#!/usr/bin/env bats
#
# Tests for skills/issue-context/folder-sessions.sh — the one rule that says
# which sessions claim a work folder, and whether each one runs.
#
# `claude` is replaced by a stub first on PATH: `claude agents --json` prints
# $LIVE_FILE, and `claude agents --json --all` prints $ALL_FILE. STUB_FAIL
# makes the first or the second read fail. Each call is logged in $CALLS, so a
# test can show that a folder with no session file reads no list. The
# sessions directory sits beside a temp settings file, so a developer's real
# sessions never change an outcome.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/folder-sessions.sh"

FIRST="4089da53-d584-438b-80f8-afbeb125a2bf"
CLEARED="bce0aa3b-a75a-4de0-910d-030528a0ec15"
OTHER="7fa0c639-1111-4222-8333-944455556666"
SELF="cfc8ea00-2d7e-4433-8674-ca4967af007a"

setup() {
  TEST_TEMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  BIN="$TEST_TEMP_DIR/bin"
  mkdir -p "$BIN"
  cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
[ "${1-} ${2-}" = "agents --json" ] || { echo "unexpected claude call: $*" >&2; exit 9; }
if [ "${3-}" = "--all" ]; then
  [ "${STUB_FAIL:-}" = "all" ] && exit 3
  cat "$ALL_FILE"
else
  [ "${STUB_FAIL:-}" = "live" ] && exit 3
  cat "$LIVE_FILE"
fi
STUB
  chmod +x "$BIN/claude"
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
  SESSIONS_DIR="$TEST_TEMP_DIR/sessions"
  mkdir -p "$SESSIONS_DIR"
  TOPIC="$TEST_TEMP_DIR/topic"
  mkdir -p "$TOPIC"
  LIVE_FILE="$TEST_TEMP_DIR/live.json"
  ALL_FILE="$TEST_TEMP_DIR/all.json"
  CALLS="$TEST_TEMP_DIR/calls.txt"
  printf '[]' > "$LIVE_FILE"
  printf '[]' > "$ALL_FILE"
  export LIVE_FILE ALL_FILE CALLS
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# session_file <session-id> <written_at> [job-session-id] [folder] — write a
# session file the way set-work-folder.sh does.
session_file() {
  local job="null"
  [ -z "${3-}" ] || job="\"$3\""
  printf '{"version":1,"folder":"%s","session_id":"%s","job_session_id":%s,"written_at":"%s"}' \
    "${4:-$TOPIC}" "$1" "$job" "$2" > "$SESSIONS_DIR/$1--t.json"
}

# row <job-id|null> <session-id> <name> <status|null> <pid|null> [kind] — one
# row of claude agents --json, with the keys of a real run.
row() {
  local id="\"$1\"" status="\"$4\""
  [ "$1" != "null" ] || id="null"
  [ "$4" != "null" ] || status="null"
  printf '{"cwd":"/x","id":%s,"kind":"%s","name":"%s","pid":%s,"sessionId":"%s","startedAt":1,"state":"blocked","status":%s,"waitingFor":null}' \
    "$id" "${6:-background}" "$3" "$5" "$2" "$status"
}

# run_sessions [self-session] [job-dir] <args...> — run the script as the
# given session, in the given job.
run_sessions() {
  local self="$1" job="$2"
  shift 2
  run --separate-stderr env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_JOB_DIR \
    ${self:+CLAUDE_CODE_SESSION_ID="$self"} ${job:+CLAUDE_JOB_DIR="$job"} \
    PATH="$BIN:$PATH" MY_CLAUDE_SKILLS_CONFIG="$CFG" STUB_FAIL="${STUB_FAIL:-}" \
    "$SCRIPT" "$@"
}

# ============================================================================
# States
# ============================================================================

@test "a live row with a process is running" {
  session_file "$FIRST" 2026-10-13T10:00:00Z
  printf '[%s]' "$(row "${FIRST:0:8}" "$FIRST" topic idle 123)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"
  run_sessions "" "" "$TOPIC"
  [ "$status" -eq 0 ]
  [ "$output" = "$FIRST	${FIRST:0:8}	topic	running" ]
}

@test "a live row with a status and no pid is running" {
  session_file "$FIRST" 2026-10-13T10:00:00Z
  printf '[%s]' "$(row "${FIRST:0:8}" "$FIRST" topic busy null)" > "$LIVE_FILE"
  run_sessions "" "" "$TOPIC"
  [ "$output" = "$FIRST	${FIRST:0:8}	topic	running" ]
}

@test "a live row with status null and pid null is retired" {
  session_file "$FIRST" 2026-10-13T10:00:00Z
  printf '[%s]' "$(row "${FIRST:0:8}" "$FIRST" topic null null)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"
  run_sessions "" "" "$TOPIC"
  [ "$output" = "$FIRST	${FIRST:0:8}	topic	retired" ]
}

@test "a session with no live row is ended, with the name of its --all row" {
  session_file "$FIRST" 2026-10-13T10:00:00Z
  printf '[%s]' "$(row "${FIRST:0:8}" "$FIRST" topic null null)" > "$ALL_FILE"
  run_sessions "" "" "$TOPIC"
  [ "$output" = "$FIRST	${FIRST:0:8}	topic	ended" ]
}

@test "a session that no row names is ended, with no job id and no name" {
  session_file "$FIRST" 2026-10-13T10:00:00Z
  run_sessions "" "" "$TOPIC"
  [ "$output" = "$FIRST	-	-	ended" ]
}

# ============================================================================
# After /clear: one job, more than one id
# ============================================================================

@test "a running session after /clear is found through its job id, with its current conversation" {
  session_file "$FIRST" 2026-10-13T10:00:00Z
  printf '[%s]' "$(row "${FIRST:0:8}" "$CLEARED" topic idle 123)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"
  run_sessions "" "" "$TOPIC"
  [ "$output" = "$CLEARED	${FIRST:0:8}	topic	running" ]
}

@test "the files of one job before and after /clear give one line" {
  session_file "$FIRST" 2026-10-13T10:00:00Z "$FIRST"
  session_file "$CLEARED" 2026-10-14T10:00:00Z "$FIRST"
  printf '[%s]' "$(row "${FIRST:0:8}" "$CLEARED" topic idle 123)" > "$LIVE_FILE"
  run_sessions "" "" "$TOPIC"
  [ "${#lines[@]}" -eq 1 ]
  [ "$output" = "$CLEARED	${FIRST:0:8}	topic	running" ]
}

@test "an ended job after /clear gives its first id, the id that wakes the job with no copy" {
  session_file "$CLEARED" 2026-10-14T10:00:00Z "$FIRST"
  printf '[%s]' "$(row "${FIRST:0:8}" "$FIRST" topic null null)" > "$ALL_FILE"
  run_sessions "" "" "$TOPIC"
  [ "$output" = "$FIRST	${FIRST:0:8}	topic	ended" ]
}

@test "an ended job with no job_session_id field gives the first id from its --all row" {
  session_file "$FIRST" 2026-10-13T10:00:00Z
  printf '[%s]' "$(row "${FIRST:0:8}" "$FIRST" topic null null)" > "$ALL_FILE"
  run_sessions "" "" "$TOPIC"
  [ "$output" = "$FIRST	${FIRST:0:8}	topic	ended" ]
}

@test "an interactive session joins by its session id, and has no job id" {
  session_file "$OTHER" 2026-10-13T10:00:00Z
  printf '[%s]' "$(row null "$OTHER" "" idle 123 interactive)" > "$LIVE_FILE"
  run_sessions "" "" "$TOPIC"
  [ "$output" = "$OTHER	-	-	running" ]
}

# ============================================================================
# Order, filters, and the caller
# ============================================================================

@test "two sessions print newest first" {
  session_file "$FIRST" 2026-10-13T10:00:00Z
  session_file "$OTHER" 2026-10-15T10:00:00Z
  printf '[%s,%s]' "$(row "${FIRST:0:8}" "$FIRST" a idle 1)" "$(row "${OTHER:0:8}" "$OTHER" b null null)" > "$LIVE_FILE"
  run_sessions "" "" "$TOPIC"
  [ "${lines[0]}" = "$OTHER	${OTHER:0:8}	b	retired" ]
  [ "${lines[1]}" = "$FIRST	${FIRST:0:8}	a	running" ]
}

@test "a session file of another folder does not count" {
  mkdir -p "$TEST_TEMP_DIR/elsewhere"
  session_file "$FIRST" 2026-10-13T10:00:00Z "" "$TEST_TEMP_DIR/elsewhere"
  run_sessions "" "" "$TOPIC"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "with no session file, the script reads no list" {
  run_sessions "" "" "$TOPIC"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$CALLS" ]
}

@test "--others leaves out the session of the caller" {
  session_file "$SELF" 2026-10-15T10:00:00Z
  session_file "$FIRST" 2026-10-13T10:00:00Z
  printf '[%s,%s]' "$(row "${SELF:0:8}" "$SELF" me idle 1)" "$(row "${FIRST:0:8}" "$FIRST" topic idle 2)" > "$LIVE_FILE"
  run_sessions "$SELF" "" --others "$TOPIC"
  [ "$output" = "$FIRST	${FIRST:0:8}	topic	running" ]
}

@test "--others leaves out the job of the caller after /clear" {
  local job="$TEST_TEMP_DIR/job"
  mkdir -p "$job"
  printf '{"sessionId":"%s"}' "$FIRST" > "$job/state.json"
  session_file "$FIRST" 2026-10-13T10:00:00Z
  printf '[%s]' "$(row "${FIRST:0:8}" "$CLEARED" topic idle 1)" > "$LIVE_FILE"
  run_sessions "$CLEARED" "$job" --others "$TOPIC"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--others leaves out the first-id file of the caller's job when no row names it" {
  local job="$TEST_TEMP_DIR/job"
  mkdir -p "$job"
  printf '{"sessionId":"%s"}' "$FIRST" > "$job/state.json"
  session_file "$FIRST" 2026-10-13T10:00:00Z
  run_sessions "$CLEARED" "$job" --others "$TOPIC"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "without --others, the caller is listed" {
  session_file "$SELF" 2026-10-15T10:00:00Z
  printf '[%s]' "$(row "${SELF:0:8}" "$SELF" me idle 1)" > "$LIVE_FILE"
  run_sessions "$SELF" "" "$TOPIC"
  [ "$output" = "$SELF	${SELF:0:8}	me	running" ]
}

@test "a folder given through a symlink matches the canonical folder" {
  ln -s "$TOPIC" "$TEST_TEMP_DIR/link"
  session_file "$FIRST" 2026-10-13T10:00:00Z
  run_sessions "" "" "$TEST_TEMP_DIR/link"
  [ "$output" = "$FIRST	-	-	ended" ]
}

@test "a session id that is not one plain token is skipped" {
  printf '{"version":1,"folder":"%s","session_id":"a b;c","written_at":"x"}' "$TOPIC" > "$SESSIONS_DIR/bad.json"
  run_sessions "" "" "$TOPIC"
  [ -z "$output" ]
}

# ============================================================================
# Errors
# ============================================================================

@test "claude agents --json fails → exit 2, H004, nothing on stdout" {
  session_file "$FIRST" 2026-10-13T10:00:00Z
  STUB_FAIL=live run_sessions "" "" "$TOPIC"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"H004"*"claude agents --json failed"* ]] || false
}

@test "claude agents --json --all fails → exit 2, H004" {
  session_file "$FIRST" 2026-10-13T10:00:00Z
  STUB_FAIL=all run_sessions "" "" "$TOPIC"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"H004"*"--all failed"* ]] || false
}

@test "a list that is not a JSON array → exit 2" {
  session_file "$FIRST" 2026-10-13T10:00:00Z
  printf 'not json' > "$LIVE_FILE"
  run_sessions "" "" "$TOPIC"
  [ "$status" -eq 2 ]
}

@test "jq missing → exit 2, H003" {
  local bin="$TEST_TEMP_DIR/nojq"
  mkdir -p "$bin"
  ln -s "$(command -v bash)" "$bin/bash"
  ln -s "$(command -v dirname)" "$bin/dirname"
  run --separate-stderr env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_JOB_DIR \
    PATH="$bin" MY_CLAUDE_SKILLS_CONFIG="$CFG" "$SCRIPT" "$TOPIC"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"H003"* ]] || false
}

@test "no folder → exit 1, H001" {
  run_sessions "" ""
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"H001"* ]] || false
}

@test "a relative folder → exit 1, H002" {
  run_sessions "" "" topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"H002"*"not an absolute path"* ]] || false
}

@test "a folder that does not exist → exit 1, H002" {
  run_sessions "" "" "$TEST_TEMP_DIR/gone"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"H002"*"not an existing directory"* ]] || false
}

@test "an unknown flag → exit 1, H001" {
  run_sessions "" "" --bogus "$TOPIC"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"H001"* ]] || false
}

@test "two folders → exit 1, H001" {
  run_sessions "" "" "$TOPIC" "$TOPIC"
  [ "$status" -eq 1 ]
}

@test "--help prints the usage" {
  run_sessions "" "" --help
  [ "$status" -eq 0 ]
  [[ "$output" == "Usage: folder-sessions.sh"* ]] || false
}
