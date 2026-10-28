#!/usr/bin/env bats
#
# Tests for skills/issue-context/session-hook.sh — the Claude Code hook that
# keeps the work folder of a session after a /clear, and warns a resumed
# session when another session holds its work folder.
#
# `claude` is replaced by a stub first on PATH: `claude agents --json` prints
# $LIVE_FILE, and `claude agents --json --all` prints $ALL_FILE. STUB_FAIL
# makes the first or the second read fail. Each call is logged in $CALLS. The
# sessions directory, the handoff directory, and the transcripts and job
# records that folder-sessions.sh reads sit beside a temp settings file, so a
# developer's real sessions never change an outcome. Each case
# runs with CLAUDE_CODE_SESSION_ID, CLAUDE_JOB_DIR, and CLAUDE_PID removed,
# and sets only what it needs.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/session-hook.sh"

OLD="4089da53-d584-438b-80f8-afbeb125a2bf"
NEW="bce0aa3b-a75a-4de0-910d-030528a0ec15"
OTHER="7fa0c639-1111-4222-8333-944455556666"
PID=4242

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
  HANDOFF_DIR="$TEST_TEMP_DIR/clear-handoff"
  TOPIC="$TEST_TEMP_DIR/topic"
  mkdir -p "$TOPIC"
  LIVE_FILE="$TEST_TEMP_DIR/live.json"
  ALL_FILE="$TEST_TEMP_DIR/all.json"
  CALLS="$TEST_TEMP_DIR/calls.txt"
  printf '[]' > "$LIVE_FILE"
  printf '[]' > "$ALL_FILE"
  export LIVE_FILE ALL_FILE CALLS
  # Without these, folder-sessions.sh reads ~/.claude/projects, and a host
  # with no such directory gets H005 for an ended session.
  mkdir -p "$TEST_TEMP_DIR/projects"
  export FOLDER_SESSIONS_PROJECTS_DIR="$TEST_TEMP_DIR/projects"
  export FOLDER_SESSIONS_JOBS_DIR="$TEST_TEMP_DIR/jobs"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# event <hook-event> <source-or-reason> <session-id> — the JSON input of one
# hook call.
event() {
  local key="source"
  [ "$1" != "SessionEnd" ] || key="reason"
  printf '{"hook_event_name":"%s","%s":"%s","session_id":"%s","cwd":"/x"}' "$1" "$key" "$2" "$3"
}

# run_hook <input> [NAME=value ...] — run the hook with <input> on stdin, in
# a clean environment plus the given variables.
run_hook() {
  local input="$1"
  shift
  run --separate-stderr env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_JOB_DIR -u CLAUDE_PID \
    PATH="$BIN:$PATH" MY_CLAUDE_SKILLS_CONFIG="$CFG" STUB_FAIL="${STUB_FAIL:-}" \
    "$@" "$SCRIPT" <<< "$input"
}

# session_file <session-id> <folder> [job-session-id] — write a session file
# the way set-work-folder.sh does.
session_file() {
  local job="null"
  [ -z "${3-}" ] || job="\"$3\""
  printf '{"version":1,"folder":"%s","session_id":"%s","job_session_id":%s,"written_at":"2026-10-18T10:00:00Z"}' \
    "$2" "$1" "$job" > "$SESSIONS_DIR/$1--t.json"
}

# files_of <session-id> — print the session files of one session id.
files_of() {
  find "$SESSIONS_DIR" -maxdepth 1 \( -name "$1.json" -o -name "$1--*.json" \) | sort
}

# row <job-id> <session-id> <name> <status|null> <pid|null> — one row of
# claude agents --json, with the keys of a real run.
row() {
  local status="\"$4\""
  [ "$4" != "null" ] || status="null"
  printf '{"cwd":"/x","id":"%s","kind":"background","name":"%s","pid":%s,"sessionId":"%s","startedAt":1,"state":"blocked","status":%s,"waitingFor":null}' \
    "$1" "$3" "$5" "$2" "$status"
}

# ============================================================================
# Inputs that the hook does not act on
# ============================================================================

@test "session-hook: jq missing exits 0 with one stderr line" {
  nojq="$(_stub_path_without "$TEST_TEMP_DIR/nojq" jq)"
  run --separate-stderr env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_JOB_DIR -u CLAUDE_PID \
    PATH="$nojq" MY_CLAUDE_SKILLS_CONFIG="$CFG" "$SCRIPT" <<< "$(event SessionEnd clear "$OLD")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "${#stderr_lines[@]}" -eq 1 ]
  [[ "$stderr" == "session-hook: jq not found"* ]] || false
}

@test "session-hook: input that is not JSON exits 0 with one stderr line" {
  run_hook 'not json'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "${#stderr_lines[@]}" -eq 1 ]
  [[ "$stderr" == "session-hook: "* ]] || false
}

@test "session-hook: JSON that is not an object exits 0 with one stderr line" {
  run_hook '["SessionStart"]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "${#stderr_lines[@]}" -eq 1 ]
  [[ "$stderr" == "session-hook: "* ]] || false
}

@test "session-hook: empty input exits 0 with one stderr line" {
  run_hook ''
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "${#stderr_lines[@]}" -eq 1 ]
}

@test "session-hook: an event outside the three cases does nothing" {
  session_file "$NEW" "$TOPIC"
  printf '[%s]' "$(row "${OTHER:0:8}" "$OTHER" other idle 123)" > "$LIVE_FILE"
  for input in "$(event SessionStart startup "$NEW")" "$(event SessionEnd logout "$NEW")" \
      "$(event SessionStart compact "$NEW")" '{"hook_event_name":"Stop","session_id":"x"}'; do
    run_hook "$input" CLAUDE_PID="$PID"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
  done
  [ ! -e "$HANDOFF_DIR" ]
  [ ! -e "$CALLS" ]
  [ "$(find "$SESSIONS_DIR" -type f | wc -l | tr -d ' ')" -eq 1 ]
}

@test "session-hook: a session_id that cannot be a file name exits 0 with one stderr line" {
  run_hook "$(event SessionEnd clear '../settings')" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "${#stderr_lines[@]}" -eq 1 ]
  [ ! -e "$HANDOFF_DIR" ]
}

# ============================================================================
# /clear
# ============================================================================

@test "session-hook: a session with no session file writes no handoff and no session file" {
  run_hook "$(event SessionEnd clear "$OLD")" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ ! -e "$HANDOFF_DIR/$PID.json" ]

  run_hook "$(event SessionStart clear "$NEW")" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ -z "$(files_of "$NEW")" ]
}

@test "session-hook: an interactive /clear carries the folder to the new session id" {
  session_file "$OLD" "$TOPIC"

  run_hook "$(event SessionEnd clear "$OLD")" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ -f "$HANDOFF_DIR/$PID.json" ]
  [ "$(jq -r .folder "$HANDOFF_DIR/$PID.json")" = "$TOPIC" ]
  [ "$(jq -r .session_id "$HANDOFF_DIR/$PID.json")" = "$OLD" ]
  jq -e '.written_at | type == "number"' "$HANDOFF_DIR/$PID.json" >/dev/null

  run_hook "$(event SessionStart clear "$NEW")" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  new_file="$(files_of "$NEW")"
  [ -n "$new_file" ]
  [ "$(jq -r .folder "$new_file")" = "$TOPIC" ]
  [ ! -e "$HANDOFF_DIR/$PID.json" ]
}

@test "session-hook: a second call for each /clear event changes nothing" {
  session_file "$OLD" "$TOPIC"
  run_hook "$(event SessionEnd clear "$OLD")" CLAUDE_PID="$PID"
  run_hook "$(event SessionEnd clear "$OLD")" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]
  [ "$(find "$HANDOFF_DIR" -type f | wc -l | tr -d ' ')" -eq 1 ]

  run_hook "$(event SessionStart clear "$NEW")" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]
  first="$(cat "$(files_of "$NEW")")"
  run_hook "$(event SessionStart clear "$NEW")" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ "$(files_of "$NEW" | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(cat "$(files_of "$NEW")")" = "$first" ]
}

@test "session-hook: a handoff file older than the maximum age is not used, and is removed" {
  mkdir -p "$HANDOFF_DIR"
  printf '{"folder":"%s","session_id":"%s","written_at":%s}' \
    "$TOPIC" "$OLD" "$(($(date +%s) - 1000))" > "$HANDOFF_DIR/$PID.json"

  run_hook "$(event SessionStart clear "$NEW")" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ -z "$(files_of "$NEW")" ]
  [ ! -e "$HANDOFF_DIR/$PID.json" ]
}

@test "session-hook: SESSION_HOOK_HANDOFF_MAX_AGE sets the maximum age" {
  mkdir -p "$HANDOFF_DIR"
  printf '{"folder":"%s","session_id":"%s","written_at":%s}' \
    "$TOPIC" "$OLD" "$(($(date +%s) - 1000))" > "$HANDOFF_DIR/$PID.json"

  run_hook "$(event SessionStart clear "$NEW")" CLAUDE_PID="$PID" SESSION_HOOK_HANDOFF_MAX_AGE=2000
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(jq -r .folder "$(files_of "$NEW")")" = "$TOPIC" ]
  [ ! -e "$HANDOFF_DIR/$PID.json" ]
}

@test "session-hook: a background /clear with no handoff takes the folder through the job state" {
  JOB="$TEST_TEMP_DIR/job"
  mkdir -p "$JOB"
  printf '{"sessionId":"%s","name":"topic"}' "$OLD" > "$JOB/state.json"
  session_file "$OLD" "$TOPIC" "$OLD"

  run_hook "$(event SessionStart clear "$NEW")" CLAUDE_PID="$PID" CLAUDE_JOB_DIR="$JOB"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  new_file="$(files_of "$NEW")"
  [ -n "$new_file" ]
  [ "$(jq -r .folder "$new_file")" = "$TOPIC" ]
  [ "$(jq -r .job_session_id "$new_file")" = "$OLD" ]
  [ -n "$(files_of "$OLD")" ]
}

@test "session-hook: a session file that already names the new id is not changed" {
  OTHER_TOPIC="$TEST_TEMP_DIR/other-topic"
  mkdir -p "$OTHER_TOPIC" "$HANDOFF_DIR"
  session_file "$NEW" "$TOPIC"
  before="$(cat "$(files_of "$NEW")")"
  printf '{"folder":"%s","session_id":"%s","written_at":%s}' \
    "$OTHER_TOPIC" "$OLD" "$(date +%s)" > "$HANDOFF_DIR/$PID.json"

  run_hook "$(event SessionStart clear "$NEW")" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ "$(files_of "$NEW" | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(cat "$(files_of "$NEW")")" = "$before" ]
  [ ! -e "$HANDOFF_DIR/$PID.json" ]
}

@test "session-hook: a folder of the old session that no longer exists gives one stderr line and no file" {
  session_file "$OLD" "$TEST_TEMP_DIR/gone"
  run_hook "$(event SessionEnd clear "$OLD")" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]

  run_hook "$(event SessionStart clear "$NEW")" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "${#stderr_lines[@]}" -eq 1 ]
  [[ "$stderr" == *"$TEST_TEMP_DIR/gone"* ]] || false
  [ -z "$(files_of "$NEW")" ]
}

# ============================================================================
# Resume
# ============================================================================

@test "session-hook: a resume with another running session in the folder returns additionalContext" {
  session_file "$OTHER" "$TOPIC"
  session_file "$NEW" "$TOPIC"
  printf '[%s]' "$(row "${OTHER:0:8}" "$OTHER" other-topic idle 123)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"

  run_hook "$(event SessionStart resume "$NEW")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.hookEventName)" = "SessionStart" ]
  context="$(printf '%s' "$output" | jq -r .hookSpecificOutput.additionalContext)"
  [[ "$context" == *"session $OTHER, job ${OTHER:0:8}, name other-topic, state running"* ]] || false
  [[ "$context" == *"/resume-agent $TOPIC"* ]] || false
  [[ "$context" != *"$NEW"* ]] || false
}

@test "session-hook: a resume with another retired session in the folder returns additionalContext" {
  session_file "$OTHER" "$TOPIC"
  session_file "$NEW" "$TOPIC"
  printf '[%s]' "$(row "${OTHER:0:8}" "$OTHER" other-topic null null)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"

  run_hook "$(event SessionStart resume "$NEW")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  context="$(printf '%s' "$output" | jq -r .hookSpecificOutput.additionalContext)"
  [[ "$context" == *"session $OTHER, job ${OTHER:0:8}, name other-topic, state retired"* ]] || false
  [[ "$context" == *"/resume-agent $TOPIC"* ]] || false
}

@test "session-hook: a resume when the only other session ended prints nothing" {
  session_file "$OTHER" "$TOPIC"
  session_file "$NEW" "$TOPIC"
  printf '[%s]' "$(row "${OTHER:0:8}" "$OTHER" other-topic null null)" > "$ALL_FILE"

  run_hook "$(event SessionStart resume "$NEW")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "session-hook: a resume when claude agents --json fails gives one stderr line and no stdout" {
  session_file "$OTHER" "$TOPIC"
  session_file "$NEW" "$TOPIC"
  STUB_FAIL=live run_hook "$(event SessionStart resume "$NEW")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "${#stderr_lines[@]}" -eq 1 ]
  [[ "$stderr" == "session-hook: could not check"* ]] || false
}

@test "session-hook: a resume of a session with no session file reads no list" {
  session_file "$OTHER" "$TOPIC"
  run_hook "$(event SessionStart resume "$NEW")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ ! -e "$CALLS" ]
}

# ============================================================================
# UserPromptSubmit: the session name and its folder name (issue 306)
# ============================================================================

# prompt_event <session-id> <title|null> [transcript] — the JSON input of a
# UserPromptSubmit call.
prompt_event() {
  local title="\"$2\""
  [ "$2" != "null" ] || title="null"
  printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s","session_title":%s,"transcript_path":"%s","prompt":"hi","cwd":"/x"}' \
    "$1" "$title" "${3:-$TEST_TEMP_DIR/none.jsonl}"
}

# title_transcript <file> <type:value> ... — a transcript with one title entry
# for each argument, in order: ai:<title> or custom:<title>.
title_transcript() {
  local file="$1" entry
  shift
  printf '{"type":"user","cwd":"/x"}\n' > "$file"
  for entry in "$@"; do
    case "$entry" in
      ai:*) printf '{"type":"ai-title","aiTitle":"%s","sessionId":"x"}\n' "${entry#ai:}" >> "$file" ;;
      custom:*) printf '{"type":"custom-title","customTitle":"%s","sessionId":"x"}\n' "${entry#custom:}" >> "$file" ;;
    esac
  done
}

TITLES_DIR_NAME="session-titles"

@test "session-hook: a prompt in a session with no session file gives no output" {
  run_hook "$(prompt_event "$NEW" an-ai-title)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ ! -e "$TEST_TEMP_DIR/$TITLES_DIR_NAME" ]
}

@test "session-hook: a prompt whose title is the folder name gives no output and reads no list" {
  session_file "$NEW" "$TOPIC"
  run_hook "$(prompt_event "$NEW" topic)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ ! -e "$CALLS" ]
}

@test "session-hook: a prompt after a new AI title gives the folder name back" {
  session_file "$NEW" "$TOPIC"
  title_transcript "$TEST_TEMP_DIR/t.jsonl" custom:topic ai:an-ai-title
  run_hook "$(prompt_event "$NEW" an-ai-title "$TEST_TEMP_DIR/t.jsonl")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.hookEventName)" = "UserPromptSubmit" ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.sessionTitle)" = "topic" ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // empty')" = "" ]
  [ "$(jq -r .set "$TEST_TEMP_DIR/$TITLES_DIR_NAME/$NEW.json")" = "topic" ]
}

@test "session-hook: a first prompt with no title gives the folder name" {
  session_file "$NEW" "$TOPIC"
  run_hook "$(prompt_event "$NEW" null)"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.sessionTitle)" = "topic" ]
}

@test "session-hook: a name that the user chose is kept, and gets one warning with /rename-agent first" {
  session_file "$NEW" "$TOPIC"
  title_transcript "$TEST_TEMP_DIR/t.jsonl" custom:topic custom:my-choice
  run_hook "$(prompt_event "$NEW" my-choice "$TEST_TEMP_DIR/t.jsonl")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.sessionTitle // empty')" = "" ]
  context="$(printf '%s' "$output" | jq -r .hookSpecificOutput.additionalContext)"
  [[ "$context" == "rename: "* ]] || false
  [[ "${context%%/launch-agent*}" == *"/rename-agent"* ]] || false
  [[ "$context" == *"Give the user these commands, and run none of them"* ]] || false
  [ "$(jq -r .warned "$TEST_TEMP_DIR/$TITLES_DIR_NAME/$NEW.json")" = "my-choice" ]
}

@test "session-hook: a repeated prompt under the same chosen name gives no second warning" {
  session_file "$NEW" "$TOPIC"
  title_transcript "$TEST_TEMP_DIR/t.jsonl" custom:my-choice
  run_hook "$(prompt_event "$NEW" my-choice "$TEST_TEMP_DIR/t.jsonl")"
  [ -n "$output" ]
  run_hook "$(prompt_event "$NEW" my-choice "$TEST_TEMP_DIR/t.jsonl")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "session-hook: a launch name with no title entry is a choice of the user" {
  session_file "$NEW" "$TOPIC"
  run_hook "$(prompt_event "$NEW" launched-name)"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.sessionTitle // empty')" = "" ]
  [[ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.additionalContext)" == "rename: "* ]] || false
}

@test "session-hook: a name that is the folder name of another folder gives /launch-agent first" {
  mkdir -p "$TEST_TEMP_DIR/second"
  printf '{"launchAgentDefaultFolder":"%s"}' "$TEST_TEMP_DIR" > "$CFG"
  session_file "$NEW" "$TOPIC"
  title_transcript "$TEST_TEMP_DIR/t.jsonl" custom:second
  run_hook "$(prompt_event "$NEW" second "$TEST_TEMP_DIR/t.jsonl")"
  [ "$status" -eq 0 ]
  context="$(printf '%s' "$output" | jq -r .hookSpecificOutput.additionalContext)"
  [[ "$context" == "moved: "* ]] || false
  [[ "${context%%/rename-agent*}" == *"/launch-agent \"$TEST_TEMP_DIR/second\""* ]] || false
}

@test "session-hook: a name that /rename-agent asked for is applied with no warning, then kept" {
  session_file "$NEW" "$TOPIC"
  mkdir -p "$TEST_TEMP_DIR/$TITLES_DIR_NAME"
  printf '{"wanted":"chosen","warned":"x"}' > "$TEST_TEMP_DIR/$TITLES_DIR_NAME/$NEW.json"
  run_hook "$(prompt_event "$NEW" an-ai-title)"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.sessionTitle)" = "chosen" ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // empty')" = "" ]
  [ "$(jq -c . "$TEST_TEMP_DIR/$TITLES_DIR_NAME/$NEW.json")" = '{"set":"chosen"}' ]

  title_transcript "$TEST_TEMP_DIR/t.jsonl" custom:chosen
  run_hook "$(prompt_event "$NEW" chosen "$TEST_TEMP_DIR/t.jsonl")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-hook: /rename-agent with no argument restores the folder name of a chosen name" {
  session_file "$NEW" "$TOPIC"
  mkdir -p "$TEST_TEMP_DIR/$TITLES_DIR_NAME"
  printf '{"wanted":"topic","warned":"my-choice"}' > "$TEST_TEMP_DIR/$TITLES_DIR_NAME/$NEW.json"
  run_hook "$(prompt_event "$NEW" my-choice)"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.sessionTitle)" = "topic" ]
}

@test "session-hook: a drift while another session holds the folder warns and does not rename" {
  session_file "$OTHER" "$TOPIC"
  session_file "$NEW" "$TOPIC"
  printf '[%s]' "$(row "${OTHER:0:8}" "$OTHER" topic idle 123)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"
  title_transcript "$TEST_TEMP_DIR/t.jsonl" ai:an-ai-title
  run_hook "$(prompt_event "$NEW" an-ai-title "$TEST_TEMP_DIR/t.jsonl")"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.sessionTitle // empty')" = "" ]
  context="$(printf '%s' "$output" | jq -r .hookSpecificOutput.additionalContext)"
  [[ "$context" == *"session $OTHER"*"/find-agent $TOPIC"* ]] || false
}

@test "session-hook: a /clear carries the title record to the new session id" {
  session_file "$OLD" "$TOPIC"
  mkdir -p "$TEST_TEMP_DIR/$TITLES_DIR_NAME"
  printf '{"set":"topic","warned":"my-choice"}' > "$TEST_TEMP_DIR/$TITLES_DIR_NAME/$OLD.json"
  run_hook "$(event SessionEnd clear "$OLD")" CLAUDE_PID="$PID"
  run_hook "$(event SessionStart clear "$NEW")" CLAUDE_PID="$PID"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(jq -c . "$TEST_TEMP_DIR/$TITLES_DIR_NAME/$NEW.json")" = '{"set":"topic","warned":"my-choice"}' ]
  [ ! -e "$TEST_TEMP_DIR/$TITLES_DIR_NAME/$OLD.json" ]
}
