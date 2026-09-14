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
# requirement; CI pins bats 1.14.0 (.github/workflows/ci.yml). The floor reads
# 1.7.0 rather than 1.5.0 because bats_require_minimum_version is itself a
# 1.7.0 command: asking for 1.5.0 names two versions, 1.5.x and 1.6.x, that
# cannot resolve the line making the request, so the suite fails while loading
# on exactly the versions the declaration claims to allow.
bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/set-work-folder.sh"
RESOLVER="$PROJECT_ROOT/skills/issue-context/get-issue-folder-path.sh"

SESSION_ID="06cb4128-c112-4696-bddb-3a52d1684a20"

# The writer's ERR_WRITE code, mirrored here so a failure assertion names the
# code rather than a message that is free to be reworded.
ERR_WRITE_CODE="S005"

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

@test "rewriting under the same slug keeps the file it just wrote" {
  # The write installs $target and only then removes the other files this
  # session owns. A cleanup that did not except $target would delete the
  # document it had just written and leave the session with no override.
  set_folder "$TOPIC" "same name"
  [ "$status" -eq 0 ]
  local other="$TEST_TEMP_DIR/second-topic"
  mkdir -p "$other"
  set_folder "$other" "same name"
  [ "$status" -eq 0 ]
  [ "$(session_file_count)" -eq 1 ]
  run jq -r .folder "$SESSIONS_DIR/${SESSION_ID}--same-name.json"
  [ "$output" = "$other" ]
}

@test "a slug change leaves only the new file, carrying the new folder" {
  set_folder "$TOPIC" "first name"
  local other="$TEST_TEMP_DIR/second-topic"
  mkdir -p "$other"
  set_folder "$other" "second name"
  [ "$status" -eq 0 ]
  [ "$(session_file_count)" -eq 1 ]
  [ ! -f "$SESSIONS_DIR/${SESSION_ID}--first-name.json" ]
  run jq -r .folder "$SESSIONS_DIR/${SESSION_ID}--second-name.json"
  [ "$output" = "$other" ]
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

@test "--clear errors rather than reporting success when the removal fails" {
  _require_enforced_permission_bits
  # Removing a file is governed by the write bit on its directory, not on the
  # file, so making the sessions directory read-only is what makes rm fail.
  set_folder "$TOPIC"
  [ "$status" -eq 0 ]
  chmod a-w "$SESSIONS_DIR"
  set_folder --clear
  local clear_status="$status" clear_stderr="$stderr"
  chmod u+w "$SESSIONS_DIR"
  [ "$clear_status" -ne 0 ]
  [[ "$clear_stderr" == *"$ERR_WRITE_CODE"* ]]
  # The old message is the whole point: the override survived and is still
  # routing this session's files, so saying none was set would be a lie.
  [[ "$clear_stderr" != *"no folder override was set"* ]]
  [ "$(session_file_count)" -eq 1 ]
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
# Every error branch reports its code
#
# kcov measures lines rather than branches, so `cmd || die "$ERR"` counts as
# covered the moment cmd runs, whether or not die ever fires. These reach the
# die side of each guard, which coverage cannot distinguish but behaviour can.
# ============================================================================

@test "a folder that exists but cannot be entered is refused" {
  _require_enforced_permission_bits
  # Mode 000 is testable with -d, which reads the parent, and unenterable by
  # cd: the gap between the existence check and canonicalisation.
  local locked="$TEST_TEMP_DIR/locked"
  mkdir -p "$locked"
  chmod 000 "$locked"
  set_folder "$locked"
  local st="$status" err="$stderr"
  chmod 755 "$locked"
  [ "$st" -ne 0 ]
  [[ "$err" == *"S003"* ]]
  [[ "$err" == *"could not be resolved"* ]]
}

@test "jq absent is refused rather than writing an unescaped file" {
  local nojq_path
  nojq_path="$(_stub_path_without "$TEST_TEMP_DIR/nojq-bin" jq)"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" PATH="$nojq_path" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    "$SCRIPT" "$TOPIC"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"S004"* ]]
  [ "$(session_file_count)" -eq 0 ]
}

@test "a sessions directory that cannot be created is reported" {
  _require_enforced_permission_bits
  local ro="$TEST_TEMP_DIR/readonly"
  mkdir -p "$ro"
  printf '%s' '{}' > "$ro/settings.json"
  chmod a-w "$ro"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$ro/settings.json" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" "$SCRIPT" "$TOPIC"
  local st="$status" err="$stderr"
  chmod u+w "$ro"
  [ "$st" -ne 0 ]
  [[ "$err" == *"$ERR_WRITE_CODE"* ]]
  # Naming the directory, not just "could not create": the mktemp failure
  # below carries a message this would otherwise match too.
  [[ "$err" == *"could not create $ro/sessions"* ]]
}

@test "a temporary file that cannot be created is reported" {
  _require_enforced_permission_bits
  # The sessions directory already exists, so mkdir -p succeeds and mktemp is
  # the first thing the read-only bit stops.
  mkdir -p "$SESSIONS_DIR"
  chmod a-w "$SESSIONS_DIR"
  set_folder "$TOPIC"
  local st="$status" err="$stderr"
  chmod u+w "$SESSIONS_DIR"
  [ "$st" -ne 0 ]
  [[ "$err" == *"$ERR_WRITE_CODE"* ]]
  [[ "$err" == *"temporary file"* ]]
}

@test "a document that cannot be composed is reported" {
  # A jq that fails only for -n: the settings loader still reads the config
  # through the real binary, so the failure lands on the compose and nowhere
  # earlier.
  local stub="$TEST_TEMP_DIR/badjq"
  mkdir -p "$stub"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'for a in "$@"; do [ "$a" = "-n" ] && exit 1; done\n'
    printf 'exec %s "$@"\n' "$(command -v jq)"
  } > "$stub/jq"
  chmod +x "$stub/jq"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" PATH="$stub:$PATH" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    "$SCRIPT" "$TOPIC"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"$ERR_WRITE_CODE"* ]]
  [[ "$stderr" == *"compose"* ]]
  [ "$(session_file_count)" -eq 0 ]
}

@test "a rename that fails is reported and leaves no session file" {
  local stub_path
  stub_path="$(_stub_failing "$TEST_TEMP_DIR/badmv" mv)"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" PATH="$stub_path" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    "$SCRIPT" "$TOPIC"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"$ERR_WRITE_CODE"* ]]
  [[ "$stderr" == *"could not write"* ]]
  [ "$(session_file_count)" -eq 0 ]
}

@test "a cleanup that fails after the write is fatal, not silent" {
  # The branch this PR added. The write succeeds and the older file survives,
  # which is the duplicate the reader refuses, so the command must not report
  # success over it.
  set_folder "$TOPIC" "first name"
  [ "$status" -eq 0 ]
  local stub_path
  stub_path="$(_stub_failing "$TEST_TEMP_DIR/badrm" rm)"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" PATH="$stub_path" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    "$SCRIPT" "$TOPIC" "second name"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"$ERR_WRITE_CODE"* ]]
  [[ "$stderr" == *"could not remove an older session file"* ]]
  # Both files are on disk: the write landed, the cleanup did not.
  [ "$(session_file_count)" -eq 2 ]
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
