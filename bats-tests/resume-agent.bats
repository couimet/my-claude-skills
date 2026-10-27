#!/usr/bin/env bats
#
# Tests for skills/resume-agent/resume-agent.sh — finding the session of a
# topic folder and making it run again.
#
# `claude` is replaced by a stub first on PATH. `claude agents --json` prints
# the file $AGENTS_FILE, `claude agents --json --all` prints $AGENTS_ALL_FILE
# when it is not empty and $AGENTS_FILE when it is, and `claude --bg --resume`
# records its arguments, one on each line, and its directory,
# prints what Claude Code 2.1.296 printed in a real restart with no flags,
# and then swaps $AGENTS_FILE for $AGENTS_AFTER, so a test sees the list before
# and after the restart. A read of the list after the restart that finds
# $AGENTS_NEXT swaps it in once, so a later read can show a name that the
# session loaded late. STUB_AGENTS_FAIL=second-all fails only the second
# `--all` read: folder-sessions.sh makes the first, and the script the second.
# The sessions directory sits beside a temp settings
# file, and the socket dir and the transcript dir are temp directories, so a
# developer's real sessions never change an outcome. Each test starts with a
# transcript of $TOPIC_SESSION that started in $REPO.

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
  [ "${STUB_AGENTS_FAIL:-0}" = "after-resume" ] && [ -e "$RESUME_ARGS" ] && { echo "agents failed" >&2; exit 3; }
  if [ "${3-}" = "--all" ]; then
    [ "${STUB_AGENTS_FAIL:-0}" = "all" ] && { echo "agents failed" >&2; exit 3; }
    if [ "${STUB_AGENTS_FAIL:-0}" = "second-all" ]; then
      echo x >> "$AGENTS_ALL_FILE.calls"
      [ "$(($(wc -l < "$AGENTS_ALL_FILE.calls")))" -lt 2 ] || { echo "agents failed" >&2; exit 3; }
    fi
    if [ -n "${AGENTS_ALL_FILE:-}" ] && [ -s "$AGENTS_ALL_FILE" ]; then
      cat "$AGENTS_ALL_FILE"
      exit 0
    fi
  fi
  cat "$AGENTS_FILE"
  if [ -e "$RESUME_ARGS" ] && [ -n "${AGENTS_NEXT:-}" ] && [ -s "$AGENTS_NEXT" ]; then
    mv "$AGENTS_NEXT" "$AGENTS_FILE"
  fi
  exit 0
fi
if [ "${1-}" = "--bg" ] && [ "${2-}" = "--resume" ]; then
  printf '%s\n' "$@" > "$RESUME_ARGS"
  pwd -P > "$RESUME_CWD"
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
  RESUME_CWD="$TEST_TEMP_DIR/resume-cwd.txt"
  JOBS_DIR="$TEST_TEMP_DIR/jobs"
  AGENTS_ALL_FILE="$TEST_TEMP_DIR/agents-all.json"
  : > "$AGENTS_ALL_FILE"
  SOCKET_DIR="$TEST_TEMP_DIR/socks"
  mkdir -p "$SOCKET_DIR"
  PROJECTS_DIR="$TEST_TEMP_DIR/projects"
  transcript "$TOPIC_SESSION" "$REPO"
  printf '[]' > "$AGENTS_FILE"
  : > "$AGENTS_AFTER"
  export AGENTS_FILE AGENTS_ALL_FILE AGENTS_NEXT RESUME_ARGS RESUME_CWD
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

# transcript <session-id> <start-dir> [later-dir] — write a transcript the way
# Claude Code does: a first line with no cwd, then one line for each cwd.
transcript() {
  mkdir -p "$PROJECTS_DIR/-proj"
  {
    printf '{"type":"permission-mode","sessionId":"%s"}\n' "$1"
    printf '{"type":"user","cwd":"%s","sessionId":"%s"}\n' "$2" "$1"
    [ -z "${3-}" ] || printf '{"type":"user","cwd":"%s","sessionId":"%s"}\n' "$3" "$1"
  } > "$PROJECTS_DIR/-proj/$1.jsonl"
}

# agent_entry <session-id> <name> <state> [status] [pid] [cwd] — one entry of
# claude agents --json, with the keys of a real run. The status defaults to
# idle, the pid to 99897, and the cwd to $REPO; the pid "null" gives an entry
# with no process, and the cwd "null" an entry with no cwd.
agent_entry() {
  local cwd="\"${6:-$REPO}\""
  [ "${6-}" != "null" ] || cwd="null"
  printf '{"pid":%s,"id":"%s","cwd":%s,"kind":"background","startedAt":1791926226508,"sessionId":"%s","name":"%s","status":"%s","state":"%s"}' \
    "${5:-99897}" "${1:0:8}" "$cwd" "$1" "$2" "${4:-idle}" "$3"
}

# run_resume [self-session] <args...> — run the script from $RUN_DIR, which
# defaults to $REPO.
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
    RESUME_AGENT_PROJECTS_DIR="$PROJECTS_DIR" RESUME_AGENT_JOBS_DIR="$JOBS_DIR" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "${RUN_DIR:-$REPO}" "$SCRIPT" "$@"
}

@test "an ended session restarts with a /rename prompt and no flag, and is reported idle under the folder name" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done)" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_ARGS")" = "$(printf '%s\n' --bg --resume "$TOPIC_SESSION" "/rename my-topic")" ]
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
  [ "${#lines[@]}" -eq 11 ]
  [ "$stderr" = "resume-agent: no socket at $SOCKET_DIR/99897.sock, so no Address line; send to the name, or ask the person" ]
}

@test "a restart runs in the start directory of the session, not in the directory of the caller" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done)" > "$AGENTS_AFTER"
  RUN_DIR="$REPO/my-topic" AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_CWD")" = "$REPO" ]
  [[ "$output" == *"Action: restarted"* ]] || false
}

@test "a session that started outside the repository of its folder restarts where it started" {
  local other="$TEST_TEMP_DIR/other-repo"
  mkdir -p "$other"
  git -C "$other" init -q
  transcript "$TOPIC_SESSION" "$other" "$REPO/my-topic"
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done idle 99897 "$other")" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_CWD")" = "$other" ]
  [[ "$stderr" != *"the script uses"* ]] || false
}

@test "the cwd of the job row wins over a transcript that starts in a subfolder" {
  transcript "$TOPIC_SESSION" "$REPO/my-topic"
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done null null)" > "$AGENTS_ALL_FILE"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done)" > "$AGENTS_AFTER"
  RUN_DIR="$REPO/my-topic" AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_CWD")" = "$REPO" ]
  [[ "$stderr" != *"the script"* ]] || false
}

@test "after a /clear, the job row is found by its job id and gives the directory" {
  local launch="$TEST_TEMP_DIR/launch"
  mkdir -p "$launch"
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  agent_entry "$TOPIC_SESSION" my-topic done null null "$launch" \
    | jq -c '[.sessionId = "'"$OTHER_SESSION"'"]' > "$AGENTS_ALL_FILE"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done idle 99897 "$launch")" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_CWD")" = "$launch" ]
}

@test "a job row whose directory is gone falls back to the transcript, and stderr says so" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done null null "$TEST_TEMP_DIR/gone")" > "$AGENTS_ALL_FILE"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done)" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_CWD")" = "$REPO" ]
  [[ "$stderr" == *"the job record of session $TOPIC_SESSION gives the directory $TEST_TEMP_DIR/gone, which does not exist; the script reads the transcript instead"* ]] || false
}

@test "claude agents --json --all fails → R004, and nothing restarts" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  STUB_AGENTS_FAIL=all run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 1 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$stderr" == *"H004"*"claude agents --json --all failed"* ]] || false
  [[ "$stderr" == *"R004"*"nothing was restarted"* ]] || false
}

@test "claude agents --json --all fails after the folder listing read it → R004 from the script, and nothing restarts" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  STUB_AGENTS_FAIL=second-all run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 1 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$stderr" != *"H004"* ]] || false
  [[ "$stderr" == *"R004"*"claude agents --json --all failed, so the state of session $TOPIC_SESSION is unknown; nothing was restarted"* ]] || false
}

# cleared_job_without_first_transcript — make $TOPIC_SESSION a cleared job
# whose job record continues in $CLEARED_SESSION, and whose job row gives no
# cwd. Only the transcript of $CLEARED_SESSION is left, so the session is
# ended, and its start directory is unknown.
cleared_job_without_first_transcript() {
  rm "$PROJECTS_DIR/-proj/$TOPIC_SESSION.jsonl"
  transcript "$CLEARED_SESSION" "$TEST_TEMP_DIR/elsewhere"
  mkdir -p "$JOBS_DIR/${TOPIC_SESSION:0:8}"
  printf '{"sessionId":"%s","resumeSessionId":"%s"}' "$TOPIC_SESSION" "$CLEARED_SESSION" \
    > "$JOBS_DIR/${TOPIC_SESSION:0:8}/state.json"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" "${1:-my-topic}" done null null null)" > "$AGENTS_ALL_FILE"
}

@test "with no transcript of the first id, a restart runs in the git top-level of the folder, and stderr says so" {
  cleared_job_without_first_transcript
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done)" > "$AGENTS_AFTER"
  RUN_DIR="$REPO/my-topic" AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_CWD")" = "$REPO" ]
  [[ "$stderr" == *"no transcript of session $TOPIC_SESSION in $PROJECTS_DIR, so its start directory is unknown; the script uses $REPO"* ]] || false
}

@test "a start directory that no longer exists falls back to the git top-level of the folder" {
  transcript "$TOPIC_SESSION" "$TEST_TEMP_DIR/gone"
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done)" > "$AGENTS_AFTER"
  RUN_DIR="$REPO/my-topic" AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_CWD")" = "$REPO" ]
  [[ "$stderr" == *"gives no existing start directory ($TEST_TEMP_DIR/gone); the script uses $REPO"* ]] || false
}

@test "a transcript with no cwd falls back to the git top-level of the folder, and names no directory" {
  {
    printf '{"type":"permission-mode","sessionId":"%s"}\n' "$TOPIC_SESSION"
    printf '{"type":"user","sessionId":"%s"}\n' "$TOPIC_SESSION"
  } > "$PROJECTS_DIR/-proj/$TOPIC_SESSION.jsonl"
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done)" > "$AGENTS_AFTER"
  RUN_DIR="$REPO/my-topic" AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_CWD")" = "$REPO" ]
  [[ "$stderr" == *"$TOPIC_SESSION.jsonl gives no existing start directory; the script uses $REPO"* ]] || false
}

@test "a transcript line that is not JSON is skipped, and the cwd after it is used" {
  local other="$TEST_TEMP_DIR/other-repo"
  mkdir -p "$other"
  {
    printf '{"type":"permission-mode","sessionId":\n'
    printf '{"type":"user","cwd":"%s","sessionId":"%s"}\n' "$other" "$TOPIC_SESSION"
  } > "$PROJECTS_DIR/-proj/$TOPIC_SESSION.jsonl"
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done idle 99897 "$other")" > "$AGENTS_AFTER"
  RUN_DIR="$REPO/my-topic" AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_CWD")" = "$other" ]
  [[ "$stderr" != *"the script uses"* ]] || false
}

@test "with no transcript of the first id, a folder in no repository restarts in the folder itself" {
  cleared_job_without_first_transcript loose
  local loose="$TEST_TEMP_DIR/loose"
  mkdir -p "$loose"
  session_file "$TOPIC_SESSION" "$loose" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" loose done idle 99897 "$loose")" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" "$loose"
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_CWD")" = "$loose" ]
}

@test "a restart that the list shows in another directory → R007 that says the session runs" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done idle 99897 "$REPO/my-topic")" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"R007"* ]] || false
  [[ "$stderr" == *"restarted in $REPO/my-topic, not in $REPO"* ]] || false
  [[ "$stderr" == *"claude stop ${TOPIC_SESSION:0:8}"* ]] || false
}

@test "a restart that the list shows with no cwd warns and succeeds" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done idle 99897 null)" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Action: restarted"* ]] || false
  [[ "$stderr" == *"gives no cwd for session $TOPIC_SESSION, so the script could not check that it runs in $REPO"* ]] || false
}

@test "a running session in another directory than its transcript, with no job cwd, restarts nothing and gives a warning" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done idle 99897 "$REPO/my-topic")" > "$AGENTS_FILE"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done idle 99897 null)" > "$AGENTS_ALL_FILE"
  run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$output" == *"Action: already running"* ]] || false
  [[ "$stderr" == *"session $TOPIC_SESSION runs in $REPO/my-topic, not in $REPO"* ]] || false
  [[ "$stderr" == *"type /cd $REPO"* ]] || false
}

@test "a running session restarts nothing and reports its state" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic working)" > "$AGENTS_FILE"
  run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$output" == *"State: working"* ]] || false
  [[ "$output" == *"Action: already running"* ]] || false
}

@test "a running session under another name is reported with its id" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" other-name idle)" > "$AGENTS_FILE"
  run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: other-name"* ]] || false
  [[ "$stderr" == *"runs under the name 'other-name', not 'my-topic'"* ]] || false
  [[ "$output" == *"Attach: claude attach ${TOPIC_SESSION:0:8}"* ]] || false
}

@test "with a name in the restart line, the list is still read again until the name loads" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" "${TOPIC_SESSION:0:8}" blocked)" > "$AGENTS_AFTER"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked)" > "$AGENTS_NEXT"
  NAME_WAIT=3 AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "" my-topic
  [ "$status" -eq 0 ]
  [ ! -e "$AGENTS_NEXT" ]
  [[ "$output" == *"Name: my-topic"* ]] || false
  [[ "$output" == *"type my-topic, and press Enter"* ]] || false
  [[ "$stderr" != *"runs under the name"* ]] || false
  [[ "$stderr" != *"did not show that name"* ]] || false
}

@test "a restart-line name that the list never shows is not reported as loaded" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" "${TOPIC_SESSION:0:8}" blocked)" > "$AGENTS_AFTER"
  NAME_WAIT=1 AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: not loaded yet"* ]] || false
  [[ "$output" != *"Open:"* ]] || false
  [[ "$stderr" == *"the restart named the session 'my-topic', but claude agents did not show that name within 1 seconds"* ]] || false
  [[ "$output" == *"Rename: if the agent view does not show my-topic, open the session and type /rename my-topic"* ]] || false
}

@test "with no name in the restart line, the list is read again until the name loads" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" "${TOPIC_SESSION:0:8}" blocked)" > "$AGENTS_AFTER"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked)" > "$AGENTS_NEXT"
  STUB_NAME="" NAME_WAIT=3 AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: my-topic"* ]] || false
  [[ "$stderr" != *"runs under the name"* ]] || false
}

@test "a name that never loads is reported as not loaded, with no Open line and no name warning" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" "${TOPIC_SESSION:0:8}" blocked)" > "$AGENTS_AFTER"
  STUB_NAME="" NAME_WAIT=1 AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: not loaded yet"* ]] || false
  [[ "$output" == *"Attach: claude attach ${TOPIC_SESSION:0:8}"* ]] || false
  [[ "$output" != *"Open:"* ]] || false
  [[ "$stderr" != *"runs under the name"* ]] || false
  [[ "$stderr" != *"the restart named the session"* ]] || false
}

@test "a running session with a socket gets an Address line, and no socket warning" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked idle 4242)" > "$AGENTS_FILE"
  make_socket 4242
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pid: 4242"* ]] || false
  [[ "$output" == *"Address: uds:$SOCKET_DIR/4242.sock"* ]] || false
  [ -z "$stderr" ]
}

@test "a listed entry with no process and no status is retired: nothing restarts, and stderr gives the attach command" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked idle null | sed 's/"status":"idle",//')" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$output" == *"Status: retired"* ]] || false
  [[ "$output" == *"Action: not restarted"* ]] || false
  [[ "$output" != *"Action: already running"* ]] || false
  [[ "$output" == *"Pid: none"* ]] || false
  [[ "$output" == *"Attach: claude attach ${TOPIC_SESSION:0:8}"* ]] || false
  [[ "$output" != *"Address:"* ]] || false
  [[ "$stderr" == *"is retired"*"wake it with claude attach ${TOPIC_SESSION:0:8}"* ]] || false
  [[ "$stderr" != *"no socket"* ]] || false
  [[ "$stderr" != *"could not check"* ]] || false
}

@test "a listed entry with a status and no process is running, with Pid none and no Address" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked busy null)" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$output" == *"Status: busy"* ]] || false
  [[ "$output" == *"Action: already running"* ]] || false
  [[ "$output" == *"Pid: none"* ]] || false
  [[ "$output" != *"Address:"* ]] || false
}

@test "a permission wait shows as Status: waiting" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked waiting)" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Status: waiting"* ]] || false
  [[ "$output" == *"State: blocked"* ]] || false
}

@test "another live session with the same name is named on stderr with its stop command" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s,%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked idle 4242)" \
    "$(agent_entry "$OTHER_SESSION" my-topic blocked idle 5151)" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"another live session also has the name 'my-topic': ${OTHER_SESSION:0:8} (pid 5151); if it is a copy, stop it with claude stop ${OTHER_SESSION:0:8}"* ]] || false
  [[ "$output" == *"Session: $TOPIC_SESSION"* ]] || false
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
  [[ "$output" == *"Session: $TOPIC_SESSION"* ]] || false
}

@test "with two sessions, the newest written_at wins and the other is named" {
  session_file "$OTHER_SESSION" "$REPO/my-topic" "2026-10-12T09:00:00Z"
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic idle)" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Session: $TOPIC_SESSION"* ]] || false
  [[ "$stderr" == *"another session also used this folder: $OTHER_SESSION"* ]] || false
}

@test "a session file for another folder does not count" {
  mkdir -p "$REPO/elsewhere"
  session_file "$TOPIC_SESSION" "$REPO/elsewhere" "2026-10-13T10:00:00Z"
  run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R003"* ]] || false
}

@test "no argument → R001" {
  run_resume ""
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R001"* ]] || false
}

@test "two arguments → R001" {
  run_resume "" my-topic extra
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R001"* ]] || false
}

@test "--help prints the usage" {
  run_resume "" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: resume-agent.sh <folder>"* ]] || false
}

@test "a folder that does not exist → R002, and nothing is created" {
  run_resume "" no-such-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R002"* ]] || false
  [ ! -e "$REPO/no-such-topic" ]
}

@test "a slug with a slash → R002" {
  run_resume "" a/b
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R002"* ]] || false
}

@test "an unknown flag → R001" {
  run_resume "" --verbose
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R001"* ]] || false
  [[ "$stderr" == *"unknown flag '--verbose'"* ]] || false
}

@test "a slug with a settings file that cannot be read → R002 that names the file" {
  printf '{ not json\n' > "$CFG"
  run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R002"* ]] || false
  [[ "$stderr" == *"the settings file $CFG could not be read"* ]] || false
}

@test "a slug with a relative launchAgentDefaultFolder → R002 that names the setting" {
  printf '%s' '{"launchAgentDefaultFolder":"topics"}' > "$CFG"
  run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R002"* ]] || false
  [[ "$stderr" == *"launchAgentDefaultFolder in $CFG is 'topics'"* ]] || false
}

@test "a slug outside a repository with no setting → R002" {
  REPO="$TEST_TEMP_DIR/plain"
  mkdir -p "$REPO/my-topic"
  run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R002"* ]] || false
  [[ "$stderr" == *"not inside a git repository"* ]] || false
}

@test "no session file for the folder → R003" {
  run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R003"* ]] || false
}

@test "claude agents --json fails → R004, and nothing restarts" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  STUB_AGENTS_FAIL=1 run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R004"* ]] || false
  [ ! -e "$RESUME_ARGS" ]
}

@test "claude agents --json fails after the restart → R006, not R004" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  STUB_AGENTS_FAIL=after-resume run_resume "" my-topic
  [ "$status" -eq 1 ]
  [ -e "$RESUME_ARGS" ]
  [[ "$stderr" == *"R006"* ]] || false
  [[ "$stderr" != *"R004"* ]] || false
  [[ "$stderr" == *"do not run claude --bg --resume"* ]] || false
}

@test "the restart fails → R005 with what claude printed" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  STUB_RESUME_FAIL=1 run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R005"* ]] || false
  [[ "$stderr" == *"resume refused"* ]] || false
}

@test "a restart that starts a copy → R005 that names the copy" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  STUB_RESUME_COPY=1 run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R005"* ]] || false
  [[ "$stderr" == *"started a copy as cfc8ea00"* ]] || false
}

@test "a restart after which the session is not listed → R005" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[]' > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R005"* ]] || false
  [[ "$stderr" == *"does not list the session"* ]] || false
}

# ============================================================================
# One rule for the state, and a session after /clear (issue 295, part 1)
# ============================================================================

# The id a /clear gave the topic session.
CLEARED_SESSION="bce0aa3b-a75a-4de0-910d-030528a0ec15"

@test "a running session after /clear is found through its job id, and is not resumed" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  agent_entry "$TOPIC_SESSION" my-topic blocked idle 4242 \
    | jq -c --arg s "$CLEARED_SESSION" '[.sessionId = $s]' > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$output" == *"Session: $CLEARED_SESSION"* ]] || false
  [[ "$output" == *"Id: ${TOPIC_SESSION:0:8}"* ]] || false
  [[ "$output" == *"Action: already running"* ]] || false
}

@test "an ended job whose newest file is under the id of a /clear resumes the first id of the job" {
  printf '{"version":1,"folder":"%s","session_id":"%s","job_session_id":"%s","written_at":"%s"}' \
    "$REPO/my-topic" "$CLEARED_SESSION" "$TOPIC_SESSION" "2026-10-14T10:00:00Z" \
    > "$SESSIONS_DIR/$CLEARED_SESSION.json"
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done null null)" > "$AGENTS_ALL_FILE"
  agent_entry "$TOPIC_SESSION" my-topic done \
    | jq -c --arg s "$CLEARED_SESSION" '[.sessionId = $s]' > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_ARGS")" = "$(printf '%s\n' --bg --resume "$TOPIC_SESSION" "/rename my-topic")" ]
  [[ "$output" == *"Action: restarted"* ]] || false
  [[ "$output" == *"Session: $CLEARED_SESSION"* ]] || false
  [[ "$stderr" != *"another session also used this folder"* ]] || false
}

@test "the session of the caller after /clear is skipped through its job" {
  local job="$TEST_TEMP_DIR/selfjob"
  mkdir -p "$job"
  printf '{"sessionId":"%s"}' "$SELF_SESSION" > "$job/state.json"
  session_file "$SELF_SESSION" "$REPO/my-topic" "2026-10-14T10:00:00Z"
  run --separate-stderr env -u CLAUDE_CODE_SESSION_ID \
    CLAUDE_CODE_SESSION_ID="$CLEARED_SESSION" CLAUDE_JOB_DIR="$job" \
    PATH="$STUB_PATH" MY_CLAUDE_SKILLS_CONFIG="$CFG" RESUME_AGENT_NAME_WAIT=0 \
    RESUME_AGENT_SOCKET_DIR="$SOCKET_DIR" RESUME_AGENT_PROJECTS_DIR="$PROJECTS_DIR" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R003"*"no session other than this one"* ]] || false
}

@test "the sessions of the folder that cannot be read → R004, and nothing restarts" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  STUB_AGENTS_FAIL=1 run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 1 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$stderr" == *"R004"* ]] || false
}

@test "a folder listing that fails with another exit code → R002, and nothing restarts" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  # The script checks the folder before it lists the sessions, so the listing
  # cannot exit 1. A jq that fails only for the join of folder-sessions.sh,
  # the one call with --argjson all, gives an exit code that is not 0 or 2.
  local real_jq
  real_jq="$(command -v jq)"
  cat > "$BIN/jq" <<STUB
#!/usr/bin/env bash
case " \$* " in
  *" --argjson all "*) exit 5 ;;
esac
exec "$real_jq" "\$@"
STUB
  chmod +x "$BIN/jq"
  run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 1 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$stderr" == *"R002"*"the sessions of $REPO/my-topic could not be listed"* ]] || false
}

# ============================================================================
# What the user needs after a restart (issue 295, part 3)
# ============================================================================

@test "a running session under the folder name gets no Rename line" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic idle)" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" != *"Rename:"* ]] || false
}

@test "a folder name with a space reaches the /rename prompt as one argument" {
  mkdir -p "$REPO/my topic"
  session_file "$TOPIC_SESSION" "$REPO/my topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" "my topic" done)" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "" "my topic"
  [ "$status" -eq 0 ]
  [ "$(cat "$RESUME_ARGS")" = "$(printf '%s\n' --bg --resume "$TOPIC_SESSION" "/rename my topic")" ]
  [[ "$output" != *"Rename:"* ]] || false
}

@test "a restarted session that the list shows under another name gets the Rename line" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" old-title idle)" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Action: restarted"* ]] || false
  [[ "$output" == *"Rename: if the agent view does not show my-topic, open the session and type /rename my-topic"* ]] || false
}

@test "a running session under another name gets the Rename line" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" old-title idle)" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rename: if the agent view does not show my-topic, open the session and type /rename my-topic"* ]] || false
}

@test "an ended record with the same name gives its removal command, and no Open line" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s,%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done null null)" \
    "$(agent_entry "$OTHER_SESSION" my-topic stopped null null)" > "$AGENTS_ALL_FILE"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done)" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" == *"Action: restarted"* ]] || false
  [[ "$output" != *"Open:"* ]] || false
  [[ "$output" == *"Attach: claude attach ${TOPIC_SESSION:0:8}"* ]] || false
  [[ "$stderr" == *"an ended job record also has the name 'my-topic': ${OTHER_SESSION:0:8}"*"claude rm ${OTHER_SESSION:0:8} removes that record and its worktree, and keeps its transcript"* ]] || false
}

@test "a live record with the same name gives no Open line" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s,%s]' "$(agent_entry "$TOPIC_SESSION" my-topic blocked idle 4242)" \
    "$(agent_entry "$OTHER_SESSION" my-topic blocked idle 5151)" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$output" != *"Open:"* ]] || false
}

@test "an ended record that continues in the restarted conversation is reported with its removal command" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  mkdir -p "$JOBS_DIR/${OTHER_SESSION:0:8}"
  printf '{"sessionId":"%s","resumeSessionId":"%s"}' "$OTHER_SESSION" "$TOPIC_SESSION" \
    > "$JOBS_DIR/${OTHER_SESSION:0:8}/state.json"
  printf '[%s,%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done null null)" \
    "$(agent_entry "$OTHER_SESSION" older-title done null null)" > "$AGENTS_ALL_FILE"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic done)" > "$AGENTS_AFTER"
  AGENTS_AFTER_SET="$AGENTS_AFTER" run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"the ended job record ${OTHER_SESSION:0:8} continues in the conversation of this session, $TOPIC_SESSION; claude rm ${OTHER_SESSION:0:8} removes that record"* ]] || false
}

@test "an older session whose job record continues in the newer conversation is named as its earlier part" {
  session_file "$OTHER_SESSION" "$REPO/my-topic" "2026-10-12T09:00:00Z"
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  mkdir -p "$JOBS_DIR/${OTHER_SESSION:0:8}"
  printf '{"sessionId":"%s","resumeSessionId":"%s"}' "$OTHER_SESSION" "$TOPIC_SESSION" \
    > "$JOBS_DIR/${OTHER_SESSION:0:8}/state.json"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic idle)" > "$AGENTS_FILE"
  printf '[%s,%s]' "$(agent_entry "$TOPIC_SESSION" my-topic idle)" \
    "$(agent_entry "$OTHER_SESSION" my-topic done null null)" > "$AGENTS_ALL_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"another session also used this folder: $OTHER_SESSION continued as $TOPIC_SESSION (not resumed; it is the earlier part of the same work)"* ]] || false
  [[ "$stderr" != *"the newest one wins"* ]] || false
}

# ============================================================================
# A session whose transcript is gone (issue 302)
# ============================================================================

# Only $TOPIC_SESSION has a transcript, so $OTHER_SESSION is gone when no
# live row names it.

@test "a gone session → R008, nothing restarts, nothing on stdout, and the advice is /launch-agent" {
  session_file "$OTHER_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 1 ]
  [ ! -e "$RESUME_ARGS" ]
  [ -z "$output" ]
  [[ "$stderr" == *"resume-agent R008 error: Claude Code deleted the transcript of session $OTHER_SESSION (no $OTHER_SESSION.jsonl in $PROJECTS_DIR)"* ]] || false
  [[ "$stderr" == *"an empty conversation with no history and no name"* ]] || false
  [[ "$stderr" == *"/launch-agent \"$REPO/my-topic\""* ]] || false
  [[ "$stderr" != *"start a session in"* ]] || false
  [[ "$stderr" != *"no session"* ]] || false
}

@test "a gone session after /clear names the conversation of its job record" {
  session_file "$OTHER_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  mkdir -p "$JOBS_DIR/${OTHER_SESSION:0:8}"
  printf '{"sessionId":"%s","resumeSessionId":"%s"}' "$OTHER_SESSION" "$CLEARED_SESSION" \
    > "$JOBS_DIR/${OTHER_SESSION:0:8}/state.json"
  printf '[%s]' "$(agent_entry "$OTHER_SESSION" my-topic done null null)" > "$AGENTS_ALL_FILE"
  run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R008"*"(no $CLEARED_SESSION.jsonl in $PROJECTS_DIR)"* ]] || false
}

@test "a gone session whose job row starts in another directory → R008 that names that directory" {
  local wt="$TEST_TEMP_DIR/worktree"
  mkdir -p "$wt"
  session_file "$OTHER_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$OTHER_SESSION" my-topic done null null "$wt")" > "$AGENTS_ALL_FILE"
  run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 1 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$stderr" == *"R008"*"start a session in $wt, and run /launch-agent \"$REPO/my-topic\" in it"* ]] || false
}

@test "a gone session whose job row starts in the git top-level of the folder → R008 with /launch-agent alone" {
  session_file "$OTHER_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$OTHER_SESSION" my-topic done null null "$REPO")" > "$AGENTS_ALL_FILE"
  run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"R008"*"/launch-agent \"$REPO/my-topic\""* ]] || false
  [[ "$stderr" != *"start a session in"* ]] || false
}

@test "a gone session whose job row read fails → R008 with /launch-agent alone, not R004" {
  session_file "$OTHER_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  STUB_AGENTS_FAIL=second-all run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 1 ]
  [ ! -e "$RESUME_ARGS" ]
  [[ "$stderr" == *"R008"*"/launch-agent \"$REPO/my-topic\""* ]] || false
  [[ "$stderr" != *"R004"* ]] || false
}

@test "a gone newest session with an older ended session → R008, and stderr names the older session" {
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-12T09:00:00Z"
  session_file "$OTHER_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  run_resume "$SELF_SESSION" my-topic
  [ "$status" -eq 1 ]
  [ ! -e "$RESUME_ARGS" ]
  [ -z "$output" ]
  [[ "$stderr" == *"another session also used this folder: $TOPIC_SESSION (not resumed; the newest one wins)"* ]] || false
  [[ "$stderr" == *"R008"*"session $OTHER_SESSION"* ]] || false
}

@test "an older gone session is marked as gone on its line" {
  session_file "$OTHER_SESSION" "$REPO/my-topic" "2026-10-12T09:00:00Z"
  session_file "$TOPIC_SESSION" "$REPO/my-topic" "2026-10-13T10:00:00Z"
  printf '[%s]' "$(agent_entry "$TOPIC_SESSION" my-topic idle)" > "$AGENTS_FILE"
  run_resume "" my-topic
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"another session also used this folder: $OTHER_SESSION (not resumed; the newest one wins; Claude Code deleted its transcript)"* ]] || false
}
