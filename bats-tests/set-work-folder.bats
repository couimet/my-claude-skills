#!/usr/bin/env bats
#
# Tests for skills/issue-context/set-work-folder.sh — writes the current
# session's folder override. Every test points MY_CLAUDE_SKILLS_CONFIG at a
# temp settings file, which puts the sessions directory beside it, so a
# developer's real ~/.my-claude-skills/sessions/ is never touched.
#
# --separate-stderr throughout: the script reports what it did on stderr and
# prints only the written file's path on stdout, and several tests assert that
# split directly.

# `run --separate-stderr` is a flagged run, which bats guarantees only from
# 1.5.0 onward. Declaring the floor turns the BW02 warning into a checked
# requirement; CI pins bats 1.14.0 (.github/workflows/ci.yml).
bats_require_minimum_version 1.5.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/set-work-folder.sh"
RESOLVER="$PROJECT_ROOT/skills/issue-context/get-issue-folder-path.sh"

SESSION_ID="06cb4128-c112-4696-bddb-3a52d1684a20"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  git checkout -q -B main
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
  SESSIONS_DIR="$TEST_TEMP_DIR/sessions"
  TOPIC="$TEST_TEMP_DIR/my-topic"
  mkdir -p "$TOPIC"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# Run the writer for SESSION_ID in a hermetic environment.
#
# Every CLAUDE_* variable the script reads is unset first. A bats run inherits
# the environment of whoever started it, and when that is a Claude Code session
# the real CLAUDE_CODE_SESSION_ID, CLAUDE_PID and CLAUDE_CODE_CHILD_SESSION are
# all set. Without -u these tests would assert on the developer's live session
# instead of the fixture, and would pass or fail depending on how they were
# launched.
CLAUDE_ENV_RESET=(env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_JOB_DIR \
  -u CLAUDE_CODE_AGENT -u CLAUDE_PID -u CLAUDE_CODE_CHILD_SESSION)

set_folder() {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    "$SCRIPT" "$@"
}

# Count the files this session owns.
session_file_count() {
  local n=0 f
  for f in "$SESSIONS_DIR/${SESSION_ID}"*.json; do
    [ -f "$f" ] && n=$((n + 1))
  done
  printf '%s' "$n"
}

# ============================================================================
# Writing
# ============================================================================

@test "no name given → file named for the session alone" {
  set_folder "$TOPIC"
  [ "$status" -eq 0 ]
  [ "$output" = "$SESSIONS_DIR/${SESSION_ID}.json" ]
  [ "${#lines[@]}" -eq 1 ]
  [ -f "$SESSIONS_DIR/${SESSION_ID}.json" ]
  [[ "$stderr" == *"$TOPIC"* ]]
}

@test "name given → file carries the slugified name" {
  set_folder "$TOPIC" "My Current Work on Foobar"
  [ "$status" -eq 0 ]
  [ "$output" = "$SESSIONS_DIR/${SESSION_ID}--my-current-work-on-foobar.json" ]
  [ -f "$output" ]
}

@test "name is bounded, so a long one cannot dwarf the session id" {
  local long="This is a deliberately very long descriptive name that runs well past any sensible filename budget"
  set_folder "$TOPIC" "$long"
  [ "$status" -eq 0 ]
  local slug="${output##*--}"
  slug="${slug%.json}"
  [ "${#slug}" -le 60 ]
  [[ "$slug" != *- ]]
}

@test "the document carries the fields the reader and a human need" {
  set_folder "$TOPIC" "some work"
  [ "$status" -eq 0 ]
  run jq -r '[.version, .folder, .session_id, .slug] | @tsv' "$SESSIONS_DIR/${SESSION_ID}--some-work.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1\t%s\t%s\tsome-work' "$TOPIC" "$SESSION_ID")" ]
}

@test "written_at is UTC and written_by records what the environment said" {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    CLAUDE_CODE_AGENT="explorer" \
    CLAUDE_PID="4242" \
    CLAUDE_CODE_CHILD_SESSION="1" \
    "$SCRIPT" "$TOPIC"
  [ "$status" -eq 0 ]
  run jq -r '[.written_at, .written_by.agent, (.written_by.pid|tostring), (.written_by.child_session|tostring)] | @tsv' \
    "$SESSIONS_DIR/${SESSION_ID}.json"
  [[ "$output" == *"Z"* ]]
  [[ "$output" == *"explorer"* ]]
  [[ "$output" == *"4242"* ]]
  [[ "$output" == *"true"* ]]
}

@test "absent agent and pid are recorded as null rather than empty strings" {
  set_folder "$TOPIC"
  run jq -r '[(.written_by.agent|type), (.written_by.pid|type)] | @tsv' \
    "$SESSIONS_DIR/${SESSION_ID}.json"
  [ "$output" = "$(printf 'null\tnull')" ]
}

@test "the folder is stored canonicalised, so a path with .. resolves once" {
  set_folder "$TEST_TEMP_DIR/my-topic/../my-topic"
  [ "$status" -eq 0 ]
  run jq -r '.folder' "$SESSIONS_DIR/${SESSION_ID}.json"
  [ "$output" = "$TOPIC" ]
}

# ============================================================================
# Slug derivation from the job state file
# ============================================================================

@test "no name → slug comes from the job state file when there is one" {
  local job="$TEST_TEMP_DIR/job"
  mkdir -p "$job"
  printf '%s' '{"name":"Routing Rework","nameSource":"auto"}' > "$job/state.json"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    CLAUDE_JOB_DIR="$job" \
    "$SCRIPT" "$TOPIC"
  [ "$status" -eq 0 ]
  [ "$output" = "$SESSIONS_DIR/${SESSION_ID}--routing-rework.json" ]
}

@test "an explicit name beats the job state file" {
  local job="$TEST_TEMP_DIR/job"
  mkdir -p "$job"
  printf '%s' '{"name":"Routing Rework"}' > "$job/state.json"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    CLAUDE_JOB_DIR="$job" \
    "$SCRIPT" "$TOPIC" "chosen by hand"
  [ "$output" = "$SESSIONS_DIR/${SESSION_ID}--chosen-by-hand.json" ]
}

@test "a job state file with no usable name leaves the slug off" {
  local job="$TEST_TEMP_DIR/job"
  mkdir -p "$job"
  printf '%s' '{"nameSource":"auto"}' > "$job/state.json"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    CLAUDE_JOB_DIR="$job" \
    "$SCRIPT" "$TOPIC"
  [ "$output" = "$SESSIONS_DIR/${SESSION_ID}.json" ]
}

@test "a malformed job state file does not stop the write" {
  local job="$TEST_TEMP_DIR/job"
  mkdir -p "$job"
  printf '%s' '{"name":' > "$job/state.json"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    CLAUDE_JOB_DIR="$job" \
    "$SCRIPT" "$TOPIC"
  [ "$status" -eq 0 ]
  [ "$output" = "$SESSIONS_DIR/${SESSION_ID}.json" ]
}

# ============================================================================
# One file per session
# ============================================================================

@test "writing twice under different slugs leaves exactly one file" {
  set_folder "$TOPIC" "first name"
  [ "$status" -eq 0 ]
  set_folder "$TOPIC" "second name"
  [ "$status" -eq 0 ]
  [ "$(session_file_count)" -eq 1 ]
  [ -f "$SESSIONS_DIR/${SESSION_ID}--second-name.json" ]
  [ ! -f "$SESSIONS_DIR/${SESSION_ID}--first-name.json" ]
}

@test "writing twice, named then unnamed, leaves exactly one file" {
  set_folder "$TOPIC" "a name"
  set_folder "$TOPIC"
  [ "$(session_file_count)" -eq 1 ]
  [ -f "$SESSIONS_DIR/${SESSION_ID}.json" ]
}

@test "another session's file is left alone" {
  set_folder "$TOPIC"
  printf '%s' '{"version":1,"folder":"/elsewhere"}' > "$SESSIONS_DIR/other-session.json"
  set_folder "$TOPIC" "renamed"
  [ -f "$SESSIONS_DIR/other-session.json" ]
}

@test "no temporary file is left behind" {
  set_folder "$TOPIC"
  run bash -c "ls -A '$SESSIONS_DIR' | grep -c '^\\.tmp-' || true"
  [ "$output" = "0" ]
}

# ============================================================================
# Clearing
# ============================================================================

@test "--clear removes this session's file" {
  set_folder "$TOPIC"
  set_folder --clear
  [ "$status" -eq 0 ]
  [ "$(session_file_count)" -eq 0 ]
  [[ "$stderr" == *"cleared"* ]]
}

@test "--clear prints nothing on stdout" {
  set_folder "$TOPIC"
  set_folder --clear
  [ -z "$output" ]
}

@test "--clear with nothing set succeeds and says so" {
  set_folder --clear
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"no folder override was set"* ]]
}

@test "--clear twice still succeeds" {
  set_folder "$TOPIC"
  set_folder --clear
  set_folder --clear
  [ "$status" -eq 0 ]
}

@test "--clear leaves another session's file alone" {
  mkdir -p "$SESSIONS_DIR"
  printf '%s' '{"version":1,"folder":"/elsewhere"}' > "$SESSIONS_DIR/other-session.json"
  set_folder "$TOPIC"
  set_folder --clear
  [ -f "$SESSIONS_DIR/other-session.json" ]
}

@test "--clear rejects a second argument" {
  set_folder --clear "$TOPIC"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"S001"* ]]
}

# ============================================================================
# Refusals
# ============================================================================

@test "a folder that does not exist is refused, and nothing is written" {
  set_folder "$TEST_TEMP_DIR/not-here"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"S003"* ]]
  [[ "$stderr" == *"not an existing directory"* ]]
  [ "$(session_file_count)" -eq 0 ]
}

@test "a relative path is refused" {
  set_folder "my-topic"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"S003"* ]]
  [[ "$stderr" == *"not an absolute path"* ]]
}

@test "a path naming a file rather than a directory is refused" {
  printf '%s' 'x' > "$TEST_TEMP_DIR/a-file"
  set_folder "$TEST_TEMP_DIR/a-file"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not an existing directory"* ]]
}

@test "no arguments prints usage and errors" {
  set_folder
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"S001"* ]]
  [[ "$stderr" == *"Usage:"* ]]
}

@test "too many arguments errors" {
  set_folder "$TOPIC" "a name" "extra"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"S001"* ]]
}

@test "an unknown flag errors" {
  set_folder --wat
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"S001"* ]]
  [[ "$stderr" == *"unknown flag"* ]]
}

@test "no session id errors rather than writing an unowned file" {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    "$SCRIPT" "$TOPIC"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"S002"* ]]
  [[ "$stderr" == *"CLAUDE_CODE_SESSION_ID"* ]]
}

@test "--help prints usage on stdout and exits 0" {
  set_folder --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ============================================================================
# The writer and the resolver agree
# ============================================================================

@test "end to end: a written override is what the resolver returns" {
  set_folder "$TOPIC" "round trip"
  [ "$status" -eq 0 ]
  git checkout -q -b issues/42
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    "$RESOLVER"
  [ "$status" -eq 0 ]
  [ "$output" = "$TOPIC" ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "end to end: clearing restores branch-derived placement" {
  set_folder "$TOPIC"
  set_folder --clear
  git checkout -q -b issues/42
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    "$RESOLVER"
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42" ]
}

@test "end to end: the writer does not require the folder to be in a repository" {
  # A session is not pinned to one repository. The writer accepts any existing
  # absolute path; the resolver is what refuses one that does not belong to the
  # repository being resolved in.
  local outside
  outside="$(mktemp -d)"
  outside="$(cd "$outside" && pwd -P)"
  set_folder "$outside"
  local write_status=$status
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    "$RESOLVER"
  local resolved="$output" resolved_stderr="$stderr"
  rm -rf "$outside"
  [ "$write_status" -eq 0 ]
  [ "$resolved" = "$TEST_TEMP_DIR/.claude-work" ]
  [[ "$resolved_stderr" == *"outside this repository"* ]]
}
