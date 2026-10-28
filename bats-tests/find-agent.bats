#!/usr/bin/env bats
#
# Tests for skills/issue-context/find-agent.sh — the verdict for a work
# folder or for the current session, and the next command.
#
# `claude` is replaced by a stub first on PATH: `claude agents --json` prints
# $LIVE_FILE, and `claude agents --json --all` prints $ALL_FILE. Each call is
# logged in $CALLS, so a test can check that the script runs no command other
# than the two list reads. The sessions directory sits beside a temp settings
# file that sets launchAgentDefaultFolder to $ROOT, and the transcript and job
# record directories are temp directories, so a developer's real sessions
# never change an outcome.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/find-agent.sh"

TOPIC_SESSION="4089da53-d584-438b-80f8-afbeb125a2bf"
OTHER_SESSION="7fa0c639-1111-4222-8333-944455556666"
SELF_SESSION="cfc8ea00-2d7e-4433-8674-ca4967af007a"

setup() {
  TEST_TEMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  BIN="$TEST_TEMP_DIR/bin"
  mkdir -p "$BIN"
  cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
[ "${1-} ${2-}" = "agents --json" ] || { echo "unexpected claude call: $*" >&2; exit 9; }
[ "${STUB_FAIL:-}" = "1" ] && exit 3
if [ "${3-}" = "--all" ]; then cat "$ALL_FILE"; else cat "$LIVE_FILE"; fi
STUB
  chmod +x "$BIN/claude"
  ROOT="$TEST_TEMP_DIR/topics"
  mkdir -p "$ROOT/my-topic" "$ROOT/other-topic"
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '{"launchAgentDefaultFolder":"%s"}' "$ROOT" > "$CFG"
  SESSIONS_DIR="$TEST_TEMP_DIR/sessions"
  mkdir -p "$SESSIONS_DIR"
  LIVE_FILE="$TEST_TEMP_DIR/live.json"
  ALL_FILE="$TEST_TEMP_DIR/all.json"
  CALLS="$TEST_TEMP_DIR/calls.txt"
  printf '[]' > "$LIVE_FILE"
  printf '[]' > "$ALL_FILE"
  PROJECTS_DIR="$TEST_TEMP_DIR/projects"
  mkdir -p "$PROJECTS_DIR/-proj"
  export LIVE_FILE ALL_FILE CALLS
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# session_file <session-id> <folder> <written_at> — write a session file the
# way set-work-folder.sh does.
session_file() {
  printf '{"version":1,"folder":"%s","session_id":"%s","job_session_id":null,"written_at":"%s"}' \
    "$2" "$1" "$3" > "$SESSIONS_DIR/$1--t.json"
}

# transcript <session-id> — write a transcript, so an ended session is not
# gone.
transcript() {
  printf '{"type":"user","cwd":"/x","sessionId":"%s"}\n' "$1" > "$PROJECTS_DIR/-proj/$1.jsonl"
}

# row <session-id> <name> <status|null> <pid|null> [kind] — one row of
# claude agents --json, with the keys of a real run.
row() {
  local status="\"$3\""
  [ "$3" != "null" ] || status="null"
  printf '{"cwd":"/x","id":"%s","kind":"%s","name":"%s","pid":%s,"sessionId":"%s","startedAt":1,"state":"blocked","status":%s}' \
    "${1:0:8}" "${5:-background}" "$2" "$4" "$1" "$status"
}

# run_find [self-session] <args...> — run the script in a clean environment.
run_find() {
  local self="$1"
  shift
  run --separate-stderr env -u CLAUDE_JOB_DIR -u CLAUDE_PID -u CLAUDE_CODE_SESSION_ID \
    ${self:+CLAUDE_CODE_SESSION_ID="$self"} \
    PATH="$BIN:$PATH" MY_CLAUDE_SKILLS_CONFIG="$CFG" STUB_FAIL="${STUB_FAIL:-}" \
    FOLDER_SESSIONS_PROJECTS_DIR="$PROJECTS_DIR" FOLDER_SESSIONS_JOBS_DIR="$TEST_TEMP_DIR/jobs" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$TEST_TEMP_DIR" "$SCRIPT" "$@"
}

# only_list_reads — 0 when each logged claude call is a list read.
only_list_reads() {
  [ ! -e "$CALLS" ] || ! grep -v -x -e 'agents --json' -e 'agents --json --all' "$CALLS"
}

# ============================================================================
# A folder
# ============================================================================

@test "find-agent: a folder with no holder gives launch" {
  run_find "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: launch" ]
  [ "${lines[1]}" = "Folder: $ROOT/my-topic" ]
  [ "${lines[2]}" = "Next: /launch-agent \"$ROOT/my-topic\"" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "find-agent: a folder that does not exist yet gives launch" {
  run_find "$SELF_SESSION" new-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: launch" ]
  [ "${lines[1]}" = "Folder: $ROOT/new-topic" ]
  [ "${lines[2]}" = "Next: /launch-agent \"$ROOT/new-topic\"" ]
}

@test "find-agent: an ended holder gives resume" {
  session_file "$TOPIC_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  transcript "$TOPIC_SESSION"
  run_find "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: resume" ]
  [ "${lines[2]}" = "Holder: $TOPIC_SESSION - ended other -" ]
  [ "${lines[3]}" = "Next: /resume-agent \"$ROOT/my-topic\"" ]
}

@test "find-agent: a gone holder gives launch" {
  session_file "$TOPIC_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  run_find "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: launch" ]
  [ "${lines[2]}" = "Holder: $TOPIC_SESSION - gone other -" ]
  [ "${lines[3]}" = "Next: /launch-agent \"$ROOT/my-topic\"" ]
}

@test "find-agent: a running holder with the folder name gives running" {
  session_file "$TOPIC_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(row "$TOPIC_SESSION" my-topic idle 123)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"
  run_find "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: running" ]
  [ "${lines[2]}" = "Holder: $TOPIC_SESSION ${TOPIC_SESSION:0:8} running other my-topic" ]
  [ "${lines[3]}" = "Next: claude attach ${TOPIC_SESSION:0:8}" ]
}

@test "find-agent: a running holder with another name gives rename" {
  session_file "$TOPIC_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(row "$TOPIC_SESSION" an-ai-title idle 123)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"
  run_find "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: rename" ]
  [ "${lines[2]}" = "Holder: $TOPIC_SESSION ${TOPIC_SESSION:0:8} running other an-ai-title" ]
  [ "${lines[3]}" = "Next: open session ${TOPIC_SESSION:0:8} (claude attach ${TOPIC_SESSION:0:8}), and run /rename-agent in it" ]
}

@test "find-agent: a retired holder gives attach" {
  session_file "$TOPIC_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(row "$TOPIC_SESSION" my-topic null null)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"
  run_find "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: attach" ]
  [ "${lines[3]}" = "Next: claude attach ${TOPIC_SESSION:0:8}" ]
}

@test "find-agent: with several holders, each is listed and the newest decides" {
  session_file "$OTHER_SESSION" "$ROOT/my-topic" "2026-10-12T10:00:00Z"
  session_file "$TOPIC_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  transcript "$OTHER_SESSION"
  printf '[%s]' "$(row "$TOPIC_SESSION" my-topic idle 123)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"
  run_find "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: running" ]
  [ "${lines[2]}" = "Holder: $TOPIC_SESSION ${TOPIC_SESSION:0:8} running other my-topic" ]
  [ "${lines[3]}" = "Holder: $OTHER_SESSION - ended other -" ]
  [ "${lines[4]}" = "Next: claude attach ${TOPIC_SESSION:0:8}" ]
}

@test "find-agent: a folder that this session holds names this session" {
  session_file "$SELF_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(row "$SELF_SESSION" my-topic idle 123 interactive)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"
  run_find "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: running" ]
  [ "${lines[2]}" = "Holder: $SELF_SESSION ${SELF_SESSION:0:8} running this my-topic" ]
  [ "${lines[3]}" = "Next: nothing; this session holds the folder" ]
}

@test "find-agent: a folder that this session holds under another name gives /rename-agent here" {
  session_file "$SELF_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(row "$SELF_SESSION" an-ai-title idle 123 interactive)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"
  run_find "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: rename" ]
  [ "${lines[3]}" = "Next: /rename-agent" ]
}

@test "find-agent: --others leaves out this session" {
  session_file "$SELF_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(row "$SELF_SESSION" my-topic idle 123 interactive)" > "$LIVE_FILE"
  cp "$LIVE_FILE" "$ALL_FILE"
  run_find "$SELF_SESSION" --others my-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: launch" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "find-agent: --others with no folder gives G001" {
  run_find "$SELF_SESSION" --others
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"G001"* ]] || false
}

@test "find-agent: a failed list read gives G004 and no stdout" {
  session_file "$TOPIC_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  STUB_FAIL=1 run_find "$SELF_SESSION" my-topic
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"G004"* ]] || false
}

# ============================================================================
# The current session
# ============================================================================

@test "find-agent: a session with no session file gives unbound" {
  run_find "$SELF_SESSION"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: unbound" ]
  [ "${lines[1]}" = "Session: $SELF_SESSION" ]
  [[ "$output" == *"Next: /launch-agent \"<folder>\", or /set-work-folder \"<folder>\""* ]] || false
}

@test "find-agent: a session whose name is its folder name gives running" {
  session_file "$SELF_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(row "$SELF_SESSION" my-topic idle 123 interactive)" > "$LIVE_FILE"
  run_find "$SELF_SESSION"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: running" ]
  [ "${lines[1]}" = "Session: $SELF_SESSION" ]
  [ "${lines[2]}" = "Name: my-topic" ]
  [ "${lines[3]}" = "Folder: $ROOT/my-topic" ]
  [ "${lines[4]}" = "Next: nothing; the name of this session is its folder name" ]
}

@test "find-agent: a session whose name differs gives rename" {
  session_file "$SELF_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(row "$SELF_SESSION" an-ai-title idle 123 interactive)" > "$LIVE_FILE"
  run_find "$SELF_SESSION"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: rename" ]
  [ "${lines[2]}" = "Name: an-ai-title" ]
  [ "${lines[4]}" = "Next: /rename-agent" ]
  [[ "${lines[5]}" == "Or: "*"/launch-agent"* ]] || false
}

@test "find-agent: a session whose name is the folder name of another folder gives moved" {
  session_file "$SELF_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  run_find "$SELF_SESSION" --title other-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Verdict: moved" ]
  [ "${lines[4]}" = "Named: $ROOT/other-topic" ]
  [ "${lines[5]}" = "Next: /launch-agent \"$ROOT/other-topic\"" ]
  [ "${lines[6]}" = "Or: /rename-agent, to keep $ROOT/my-topic and its name my-topic" ]
  [ ! -e "$CALLS" ]
}

@test "find-agent: no session id gives G002" {
  run_find "" --check
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"G002"* ]] || false
}

# ============================================================================
# --check
# ============================================================================

@test "find-agent: --check on a match exits 0 with no output and reads no list" {
  session_file "$SELF_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  run_find "$SELF_SESSION" --check --title my-topic
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ ! -e "$CALLS" ]
}

@test "find-agent: --check for a session with no session file exits 0" {
  run_find "$SELF_SESSION" --check --title anything
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "find-agent: --check on another name exits 1 with one line that gives /rename-agent first" {
  session_file "$SELF_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  run_find "$SELF_SESSION" --check --title an-ai-title
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == "rename: "* ]] || false
  first="${lines[0]%%/launch-agent*}"
  [[ "$first" == *"/rename-agent"* ]] || false
}

@test "find-agent: --check on the folder name of another folder exits 1 with one line that gives /launch-agent first" {
  session_file "$SELF_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  run_find "$SELF_SESSION" --check --title other-topic
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == "moved: "* ]] || false
  first="${lines[0]%%/rename-agent*}"
  [[ "$first" == *"/launch-agent \"$ROOT/other-topic\""* ]] || false
}

@test "find-agent: --check with no --title reads the name from the list" {
  session_file "$SELF_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(row "$SELF_SESSION" my-topic idle 123 interactive)" > "$LIVE_FILE"
  run_find "$SELF_SESSION" --check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -e "$CALLS" ]
}

# ============================================================================
# No action and usage
# ============================================================================

@test "find-agent: no mode runs a command other than a list read" {
  session_file "$TOPIC_SESSION" "$ROOT/my-topic" "2026-10-13T10:00:00Z"
  session_file "$SELF_SESSION" "$ROOT/other-topic" "2026-10-13T10:00:00Z"
  transcript "$TOPIC_SESSION"
  printf '[%s]' "$(row "$SELF_SESSION" an-ai-title idle 123 interactive)" > "$LIVE_FILE"
  run_find "$SELF_SESSION" my-topic
  run_find "$SELF_SESSION"
  run_find "$SELF_SESSION" --check
  only_list_reads || false
  run grep -E '^[^#]*(launch|resume|rename)-agent\.sh' "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "find-agent: --help prints the usage and exits 0" {
  run_find "$SELF_SESSION" --help
  [ "$status" -eq 0 ]
  [[ "$output" == "Usage: find-agent.sh"* ]] || false
}

@test "find-agent: an unknown flag gives G001" {
  run_find "$SELF_SESSION" --nope
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"G001"* ]] || false
}

@test "find-agent: --check with a folder gives G001" {
  run_find "$SELF_SESSION" --check my-topic
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"G001"* ]] || false
}
