#!/usr/bin/env bats
#
# Tests for skills/resume-agent/resume-agent.sh — finding the session of a
# topic folder and making it run again.
#
# `claude` is replaced by a stub first on PATH. `claude agents --json` prints
# the file $AGENTS_FILE, and `claude --bg --resume` records its arguments,
# prints what Claude Code 2.1.296 printed in a real restart with no flags,
# and then swaps $AGENTS_FILE for $AGENTS_AFTER, so a test sees the list before
# and after the restart. A read of the list that finds $AGENTS_NEXT swaps it
# in once, so a later read can show a name that the session loaded late. The
# sessions directory sits beside a temp settings file, and the socket dir is a
# temp directory, so a developer's real sessions never change an outcome.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/resume-agent/resume-agent.sh"

TOPIC_SESSION="4089da53-d584-438b-80f8-afbeb125a2bf"
OTHER_SESSION="7fa0c639-1111-4222-8333-944455556666"
SELF_SESSION="cfc8ea00-2d7e-4433-8674-ca4967af007a"

claude_stub() {
  cat > "$1/claude" <<'STUB'
#!/usr/bin/env bash
if [ "${1-}" = "agents" ] && [ "${2-}" = "--json" ]; then
  [ "${STUB_AGENTS_FAIL:-0}" = "1" ] && { echo "agents failed" >&2; exit 3; }
  cat "$AGENTS_FILE"
  if [ -n "${AGENTS_NEXT:-}" ] && [ -s "$AGENTS_NEXT" ]; then
    mv "$AGENTS_NEXT" "$AGENTS_FILE"
  fi
  exit 0
fi
if [ "${1-}" = "--bg" ] && [ "${2-}" = "--resume" ]; then
  printf '%s\n' "$*" > "$RESUME_ARGS"
  [ "${STUB_RESUME_FAIL:-0}" = "1" ] && { echo "resume refused" >&2; exit 5; }
  if [ "${STUB_RESUME_COPY:-0}" = "1" ]; then
    echo "note: background session ${3:0:8} keeps its own saved options, so the flags you passed started a copy as cfc8ea00. Without flags, the same command continues ${3:0:8} itself."
  else
    echo "note: woke session ${3:0:8} with its saved options (--name)."
  fi
  if [ -n "${STUB_NAME:-}" ]; then
    printf 'backgrounded · %s · %s (idle — send a prompt to start)\n' "${3:0:8}" "$STUB_NAME"
  else
    printf 'backgrounded · %s (idle — send a prompt to start)\n' "${3:0:8}"
  fi
  printf '  claude agents             list sessions\n'
  printf '  claude attach %s    open in this terminal\n' "${3:0:8}"
  [ -z "${AGENTS_AFTER:-}" ] || cp "$AGENTS_AFTER" "$AGENTS_FILE"
  exit 0
fi
echo "unexpected claude call: $*" >&2
exit 9
STUB
  chmod +x "$1/claude"
}

setup() {
  TEST_TEMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  BIN="$TEST_TEMP_DIR/bin"
  mkdir -p "$BIN"
  claude_stub "$BIN"
  STUB_PATH="$BIN:$PATH"
  REPO="$TEST_TEMP_DIR/repo"
  mkdir -p "$REPO/my-topic"
  git -C "$REPO" init -q
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
  SESSIONS_DIR="$TEST_TEMP_DIR/sessions"
  mkdir -p "$SESSIONS_DIR"
  AGENTS_FILE="$TEST_TEMP_DIR/agents.json"
  AGENTS_AFTER="$TEST_TEMP_DIR/agents-after.json"
  AGENTS_NEXT="$TEST_TEMP_DIR/agents-next.json"
  RESUME_ARGS="$TEST_TEMP_DIR/resume-args.txt"
  SOCKET_DIR="$TEST_TEMP_DIR/socks"
  mkdir -p "$SOCKET_DIR"
  printf '[]' > "$AGENTS_FILE"
  : > "$AGENTS_AFTER"
  export AGENTS_FILE AGENTS_NEXT RESUME_ARGS
}

teardown() {
  if [ -n "${SOCKET_PID:-}" ]; then
    kill "$SOCKET_PID" 2>/dev/null || true
    wait "$SOCKET_PID" 2>/dev/null || true
  fi
}

# make_socket <pid> — create a listening Unix socket at $SOCKET_DIR/<pid>.sock,
# the path a real session's cross-session socket has. python3 makes it,
# because bash and the BSD and GNU nc variants have no common way to.
make_socket() {
  python3 -c 'import socket,sys,time; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(1); time.sleep(60)' \
    "$SOCKET_DIR/$1.sock" &
  SOCKET_PID=$!
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -S "$SOCKET_DIR/$1.sock" ] && return 0
    sleep 0.1
  done
  return 1
}

# session_file <session-id> <folder> <written_at> — write a session file the
# way set-work-folder.sh does.
session_file() {
  printf '{"version":1,"folder":"%s","session_id":"%s","slug":"t","written_at":"%s"}' \
    "$2" "$1" "$3" > "$SESSIONS_DIR/$1--t.json"
}

# agent_entry <session-id> <name> <state> [status] [pid] — one entry of
# claude agents --json, with the keys of a real run. The status defaults to
# idle and the pid to 99897; the pid "null" gives an entry with no process.
agent_entry() {
  printf '{"pid":%s,"id":"%s","cwd":"%s","kind":"background","startedAt":1791926226508,"sessionId":"%s","name":"%s","status":"%s","state":"%s"}' \
    "${5:-99897}" "${1:0:8}" "$REPO" "$1" "$2" "${4:-idle}" "$3"
}

# run_resume [self-session] <args...> — run the script from $REPO.
run_resume() {
  local self="$1"
  shift
  run --separate-stderr env -u CLAUDE_JOB_DIR -u CLAUDE_CODE_AGENT -u CLAUDE_PID \
    -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ID \
    ${self:+CLAUDE_CODE_SESSION_ID="$self"} \
    PATH="$STUB_PATH" MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    AGENTS_AFTER="${AGENTS_AFTER_SET:-}" \
    STUB_AGENTS_FAIL="${STUB_AGENTS_FAIL:-0}" STUB_RESUME_FAIL="${STUB_RESUME_FAIL:-0}" \
    STUB_RESUME_COPY="${STUB_RESUME_COPY:-0}" STUB_NAME="${STUB_NAME-my-topic}" \
    RESUME_AGENT_NAME_WAIT="${NAME_WAIT:-0}" RESUME_AGENT_SOCKET_DIR="$SOCKET_DIR" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" "$@"
}

@test "an ended session restarts with no flag and is reported idle under the folder name" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done)" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_ARGS")" = "--bg --resume $TOPIC_SESSION" ]
  [ "${lines[0]}" = "Folder: $REPO/my-topic" ]
  [ "${lines[1]}" = "Session: $TOPIC_SESSION" ]
  [ "${lines[2]}" = "Id: ${TOPIC_SESSION:0:8}" ]
  [ "${lines[3]}" = "Name: my-topic" ]
  [ "${lines[4]}" = "Status: idle" ]
  [ "${lines[5]}" = "State: done" ]
  [ "${lines[6]}" = "Action: restarted" ]
  [ "${lines[7]}" = "Pid: 99897" ]
  [ "${lines[8]}" = "Attach: claude attach ${TOPIC_SESSION:0:8}" ]
  [ "${lines[9]}" = "Open: in the agent view (claude agents), press Ctrl+F, type my-topic, and press Enter" ]
  [ "${lines[10]}" = "Note: do not run claude --bg --resume ${TOPIC_SESSION:0:8}: the session runs, and a resume starts a copy" ]
  [ "$stderr" = "resume-agent: no socket at $SOCKET_DIR/99897.sock, so no Address line; send to the name, or ask the person" ]
}

@test "a running session restarts nothing and reports its state" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic working)" > "$AGENTS_FILE"
  run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$output" == *"State: working"* ]]
  [[ "$output" == *"Action: already running"* ]]
}

@test "a running session under another name is reported with its id" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" other-name idle)" > "$AGENTS_FILE"
  run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: other-name"* ]]
  [[ "$stderr" == *"runs under the name 'other-name', not 'my-topic'"* ]]
  [[ "$output" == *"Attach: claude attach ${TOPIC_SESSION:0:8}"* ]]
}

@test "the name comes from the restart line while the list still shows the short id" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" "${TOPIC_SESSION:0:8}" blocked)" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: my-topic"* ]]
  [[ "$output" == *"type my-topic, and press Enter"* ]]
  [[ "$stderr" != *"runs under the name"* ]]
}

@test "with no name in the restart line, the list is read again until the name loads" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" "${TOPIC_SESSION:0:8}" blocked)" > "$AGENTS_AFTER"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked)" > "$AGENTS_NEXT"
  STUB_NAME="" NAME_WAIT=3 AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: my-topic"* ]]
  [[ "$stderr" != *"runs under the name"* ]]
}

@test "a name that never loads is reported as not loaded, with no Open line and no name warning" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" "${TOPIC_SESSION:0:8}" blocked)" > "$AGENTS_AFTER"
  STUB_NAME="" NAME_WAIT=1 AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: not loaded yet"* ]]
  [[ "$output" == *"Attach: claude attach ${TOPIC_SESSION:0:8}"* ]]
  [[ "$output" != *"Open:"* ]]
  [[ "$stderr" != *"runs under the name"* ]]
}

@test "a running session with a socket gets an Address line, and no socket warning" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked idle 4242)" > "$AGENTS_FILE"
  make_socket 4242
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pid: 4242"* ]]
  [[ "$output" == *"Address: uds:$SOCKET_DIR/4242.sock"* ]]
  [ -z "$stderr" ]
}

@test "a listed entry with no process gets Pid none, status unknown, and no Address" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked idle null | sed 's/"status":"idle",//')" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$output" == *"Status: unknown"* ]]
  [[ "$output" == *"Pid: none"* ]]
  [[ "$output" != *"Address:"* ]]
  [[ "$stderr" != *"no socket"* ]]
}

@test "a permission wait shows as Status: waiting" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked waiting)" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Status: waiting"* ]]
  [[ "$output" == *"State: blocked"* ]]
}

@test "another live session with the same name is named on stderr with its stop command" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s,%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked idle 4242)" \
    "$(agent_entry "$OTHER_SESSION" my-topic blocked idle 5151)" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"another live session also has the name 'my-topic': ${OTHER_SESSION:0:8} (pid 5151); if it is a copy, stop it with claude stop ${OTHER_SESSION:0:8}"* ]]
  [[ "$output" == *"Session: $TOPIC_SESSION"* ]]
}

@test "an absolute folder works, with a trailing slash" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic idle)" > "$AGENTS_FILE"
  run_resume "" "$REPO/my-topic/"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Folder: $REPO/my-topic" ]
}

@test "a slug resolves under launchAgentDefaultFolder when it is set" {
  mkdir -p "$TEST_TEMP_DIR/topics/my-topic"
  printf '{"launchAgentDefaultFolder":"%s"}' "$TEST_TEMP_DIR/topics" > "$CFG"
  session_file "$TOPIC_SESSION" "$TEST_TEMP_DIR/topics/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic idle)" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Folder: $TEST_TEMP_DIR/topics/my-topic" ]
}

@test "the file of the calling session is skipped" {
  session_file "$SELF_SESSION" "$REPO/my-topic" "2026-10-13T12:00:00Z"
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic idle)" > "$AGENTS_FILE"
  run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Session: $TOPIC_SESSION"* ]]
}

@test "with two sessions, the newest written_at wins and the other is named" {
  session_file "$OTHER_SESSION" "$REPO/my-topic" "2026-10-12T09:00:00Z"
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic idle)" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Session: $TOPIC_SESSION"* ]]
  [[ "$stderr" == *"another session also used this folder: $OTHER_SESSION"* ]]
}

@test "a session file for another folder does not count" {
  mkdir -p "$REPO/elsewhere"
  session_file "$TOPIC_SESSION" "$REPO/elsewhere" "2026-10-13T10:00:00Z"
  run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R003"* ]]
}

@test "no argument → R001" {
  run_resume ""
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R001"* ]]
}

@test "two arguments → R001" {
  run_resume "" my-topic extra
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R001"* ]]
}

@test "--help prints the usage" {
  run_resume "" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: resume-agent.sh <folder>"* ]]
}

@test "a folder that does not exist → R002, and nothing is created" {
  run_resume "" no-such-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R002"* ]]
  [ ! -e "$REPO/no-such-topic" ]
}

@test "a slug with a slash → R002" {
  run_resume "" a/b
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R002"* ]]
}

@test "no session file for the folder → R003" {
  run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R003"* ]]
}

@test "claude agents --json fails → R004, and nothing restarts" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  STUB_AGENTS_FAIL=1 run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R004"* ]]
  [ ! -e "$RESUME_ARGS" ]
}

@test "the restart fails → R005 with what claude printed" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  STUB_RESUME_FAIL=1 run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R005"* ]]
  [[ "$stderr" == *"resume refused"* ]]
}

@test "a restart that starts a copy → R005 that names the copy" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  STUB_RESUME_COPY=1 run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R005"* ]]
  [[ "$stderr" == *"started a copy as cfc8ea00"* ]]
}

@test "a restart after which the session is not listed → R005" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[]' > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R005"* ]]
  [[ "$stderr" == *"does not list the session"* ]]
}
