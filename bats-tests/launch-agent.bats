#!/usr/bin/env bats
#
# Tests for skills/launch-agent/launch-agent.sh — folder resolution, the
# near-match slug guard, prompt resolution and rotation, preamble composition,
# and dispatch.
#
# `claude` is replaced by a stub first on PATH that records its arguments and
# its working directory, so every dispatch assertion is made without starting
# a real background session.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/launch-agent/launch-agent.sh"

# claude_stub <dir> — write a stub `claude` that records "$*" to $ARGS_FILE and
# its working directory to $CWD_FILE, then prints a job id. Set STUB_FAIL=1 in
# the environment to make it exit non-zero instead, and STUB_SILENT=1 to make
# it succeed while printing nothing.
claude_stub() {
  cat > "$1/claude" <<'STUB'
#!/usr/bin/env bash
[ -z "${ARGS_FILE:-}" ] || printf '%s\n' "$*" > "$ARGS_FILE"
[ -z "${CWD_FILE:-}" ] || pwd > "$CWD_FILE"
if [ "${STUB_FAIL:-0}" = "1" ]; then
  echo "launch refused" >&2
  exit 7
fi
[ "${STUB_SILENT:-0}" = "1" ] || echo "bg_deadbeef"
STUB
  chmod +x "$1/claude"
}

setup() {
  # Canonicalised, because the script reports the folder it resolved with
  # `pwd -P` and macOS hands mktemp a /var path that is a symlink to
  # /private/var. Without this every path assertion below compares the two
  # spellings of one directory and fails.
  TEST_TEMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  BIN="$TEST_TEMP_DIR/bin"
  mkdir -p "$BIN"
  claude_stub "$BIN"
  ARGS_FILE="$TEST_TEMP_DIR/claude-args.txt"
  CWD_FILE="$TEST_TEMP_DIR/claude-cwd.txt"
  export ARGS_FILE CWD_FILE
  STUB_PATH="$BIN:$PATH"

  # A repository to launch from. `git init` alone is enough: every path this
  # script takes asks git only for --show-toplevel and --git-common-dir.
  REPO="$TEST_TEMP_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# run_in <dir> <args...> — run the script from <dir> with the stubbed PATH.
run_in() {
  local dir="$1"
  shift
  run env PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" \
    bash -c 'cd "$1" && shift && exec "$@"' _ "$dir" "$SCRIPT" "$@"
}

# ============================================================================
# Usage
# ============================================================================

@test "--help prints usage and exits 0" {
  run_in "$REPO" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: launch-agent.sh"* ]]
}

@test "no arguments → L001, usage on stderr" {
  run_in "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]]
  [[ "$output" == *"a folder is required"* ]]
}

@test "folder but no prompt → L001" {
  run_in "$REPO" topic
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]]
  [[ "$output" == *"a task prompt is required"* ]]
}

@test "leading flag instead of a folder → L001" {
  run_in "$REPO" --name thing "do it"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]]
  [[ "$output" == *"the folder comes first"* ]]
}

@test "--name without a value → L001" {
  run_in "$REPO" topic --name
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]]
}

# ============================================================================
# Folder resolution
# ============================================================================

@test "slug resolves to <repo-root>/<slug>, not into .claude-work" {
  run_in "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Folder: $REPO/my-topic"* ]]
  [ -d "$REPO/my-topic" ]
  [ ! -d "$REPO/.claude-work/my-topic" ]
}

@test "slug resolves against the main checkout when run from a subdirectory" {
  mkdir -p "$REPO/src/deep"
  run_in "$REPO/src/deep" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Folder: $REPO/my-topic"* ]]
}

@test "absolute path is used as given, outside any repository" {
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_in "$REPO" "$target" "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Folder: $target"* ]]
  [ -d "$target" ]
}

@test "absolute path with a trailing slash still names the job after the basename" {
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_in "$REPO" "$target/" "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: topic"* ]]
}

@test "existing folder is reused, not refused" {
  mkdir -p "$REPO/my-topic"
  run_in "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Folder: $REPO/my-topic"* ]]
}

@test "folder path that exists as a regular file → L002, nothing written" {
  : > "$TEST_TEMP_DIR/afile"
  run_in "$REPO" "$TEST_TEMP_DIR/afile" "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"is not a directory"* ]]
  [ ! -f "$ARGS_FILE" ]
}

@test "slug outside a git repository → L002 asking for an absolute path" {
  outside="$TEST_TEMP_DIR/no-repo"
  mkdir -p "$outside"
  run_in "$outside" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"pass an absolute path instead"* ]]
  [ ! -d "$outside/my-topic" ]
}

@test "slug containing a separator → L002, nothing created" {
  run_in "$REPO" team/onboarding "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"is not a single path component"* ]]
  [ ! -d "$REPO/team" ]
}

@test "slug of .. → L002, nothing created outside the root" {
  run_in "$REPO" .. "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"is not a topic name"* ]]
}

# ============================================================================
# The near-match slug guard
# ============================================================================

@test "slug that normalizes onto an existing sibling → L002 naming the sibling" {
  mkdir -p "$REPO/agent_launch_skill"
  run_in "$REPO" agent-launch-skill "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"nearly matches the existing 'agent_launch_skill'"* ]]
  [ ! -d "$REPO/agent-launch-skill" ]
}

@test "case-only difference is a near match too" {
  mkdir -p "$REPO/MyTopic"
  run_in "$REPO" mytopic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nearly matches the existing 'MyTopic'"* ]]
}

@test "exact match is not a refusal: a second agent joins an existing topic" {
  mkdir -p "$REPO/my-topic"
  run_in "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
}

@test "a regular file that normalizes onto the slug does not refuse it" {
  : > "$REPO/my_topic"
  run_in "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ -d "$REPO/my-topic" ]
}

@test "an absolute path skips the guard, which is the way past a refusal" {
  mkdir -p "$REPO/agent_launch_skill"
  run_in "$REPO" "$REPO/agent-launch-skill" "do the thing"
  [ "$status" -eq 0 ]
  [ -d "$REPO/agent-launch-skill" ]
}

# ============================================================================
# Prompt resolution
# ============================================================================

@test "multi-word prompt is written verbatim" {
  run_in "$REPO" my-topic "do the thing" "and then another"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "do the thing and then another" ]
}

@test "single token naming a readable file contributes that file's content" {
  printf 'line one\nline two\n' > "$TEST_TEMP_DIR/prompt.txt"
  run_in "$REPO" my-topic "$TEST_TEMP_DIR/prompt.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "$(printf 'line one\nline two')" ]
  [[ "$(cat "$ARGS_FILE")" == *"line two"* ]]
}

@test "path-shaped single token naming nothing → L003, nothing written" {
  run_in "$REPO" my-topic ./plans/lanch-prompt.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"L003"* ]]
  [[ "$output" == *"looks like a file path but names no readable file"* ]]
  [ ! -d "$REPO/my-topic" ]
  [ ! -f "$ARGS_FILE" ]
}

@test "unreadable file at a path-shaped token → L003 rather than a literal prompt" {
  _require_enforced_permission_bits
  printf 'secret\n' > "$TEST_TEMP_DIR/prompt.md"
  chmod 000 "$TEST_TEMP_DIR/prompt.md"
  run_in "$REPO" my-topic "$TEST_TEMP_DIR/prompt.md"
  chmod 644 "$TEST_TEMP_DIR/prompt.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L003"* ]]
}

@test "one-word literal prompt that is not path-shaped passes through" {
  run_in "$REPO" my-topic triage
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "triage" ]
}

@test "empty prompt → L003, nothing created" {
  run_in "$REPO" my-topic ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"L003"* ]]
  [ ! -d "$REPO/my-topic" ]
}

# ============================================================================
# Prompt file rotation
# ============================================================================

@test "existing prompt is archived under a stamp and the plain name holds the latest" {
  mkdir -p "$REPO/my-topic"
  printf 'the earlier prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  run_in "$REPO" my-topic "the newer prompt"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "the newer prompt" ]
  archived="$(find "$REPO/my-topic" -name 'prompt-new-agent-launch.*.txt')"
  [ -n "$archived" ]
  [ "$(cat "$archived")" = "the earlier prompt" ]
}

@test "archive name is stamped from the archived file's own mtime" {
  mkdir -p "$REPO/my-topic"
  printf 'the earlier prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  touch -t 202001021530.45 "$REPO/my-topic/prompt-new-agent-launch.txt"
  run_in "$REPO" my-topic "the newer prompt"
  [ "$status" -eq 0 ]
  [ -f "$REPO/my-topic/prompt-new-agent-launch.20200102-153045.txt" ]
}

@test "an archive name already taken gets a suffix rather than the earlier prompt" {
  mkdir -p "$REPO/my-topic"
  printf 'the earlier prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  touch -t 202001021530.45 "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'an even earlier prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.20200102-153045.txt"
  run_in "$REPO" my-topic "the newer prompt"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.20200102-153045.txt")" = "an even earlier prompt" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.20200102-153045-001.txt")" = "the earlier prompt" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "the newer prompt" ]
}

# ============================================================================
# The display name
# ============================================================================

@test "display name defaults to the folder basename and reaches claude" {
  run_in "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: my-topic"* ]]
  [[ "$(cat "$ARGS_FILE")" == *"--name my-topic"* ]]
}

@test "--name overrides the default" {
  run_in "$REPO" my-topic --name "Nightly sweep" "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: Nightly sweep"* ]]
  [[ "$(cat "$ARGS_FILE")" == *"--name Nightly sweep"* ]]
}

# ============================================================================
# The child's working directory and prompt
# ============================================================================

@test "child starts in the repository root that contains the folder" {
  run_in "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "$(cat "$CWD_FILE")" = "$(cd "$REPO" && pwd -P)" ]
}

@test "child starts in the folder itself when it is in no repository" {
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_in "$REPO" "$target" "do the thing"
  [ "$status" -eq 0 ]
  [ "$(cat "$CWD_FILE")" = "$(cd "$target" && pwd -P)" ]
}

@test "preamble names the folder, the set-work-folder call, and the saved prompt" {
  run_in "$REPO" my-topic --name "Topic run" "do the thing"
  [ "$status" -eq 0 ]
  args="$(cat "$ARGS_FILE")"
  [[ "$args" == *"Your work folder is $REPO/my-topic."* ]]
  [[ "$args" == *"set-work-folder.sh \"$REPO/my-topic\" \"Topic run\""* ]]
  [[ "$args" == *"already saved at $REPO/my-topic/prompt-new-agent-launch.txt"* ]]
  [[ "$args" == *"do the thing"* ]]
}

@test "CLAUDE.md sentence appears when the child's working directory has one" {
  printf 'repo rules\n' > "$REPO/CLAUDE.md"
  run_in "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$(cat "$ARGS_FILE")" == *"Then read $REPO/CLAUDE.md and follow it."* ]]
}

@test "CLAUDE.md sentence is absent when there is no such file" {
  run_in "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$(cat "$ARGS_FILE")" != *"and follow it"* ]]
}

# ============================================================================
# Dispatch
# ============================================================================

@test "success reports the job id and the attach command" {
  run_in "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Job: bg_deadbeef"* ]]
  [[ "$output" == *"Attach: claude attach bg_deadbeef"* ]]
}

@test "the resolved folder is the first line of output" {
  run_in "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Folder: $REPO/my-topic" ]
}

@test "dispatch failure → exit 1, folder and prompt kept, pasteable command printed" {
  run env PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" STUB_FAIL=1 \
    bash -c 'cd "$1" && shift && exec "$@"' _ "$REPO" "$SCRIPT" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L004"* ]]
  [[ "$output" == *"claude --bg --name 'my-topic'"* ]]
  [ -d "$REPO/my-topic" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "do the thing" ]
}

@test "a launch that prints no id → L004 rather than an attach command for nothing" {
  run env PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" STUB_SILENT=1 \
    bash -c 'cd "$1" && shift && exec "$@"' _ "$REPO" "$SCRIPT" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L004"* ]]
  [[ "$output" == *"reported no job id"* ]]
}

@test "claude missing from PATH is a dispatch failure, and the prompt survives it" {
  bare="$TEST_TEMP_DIR/bare"
  _stub_path_without "$bare" claude >/dev/null
  run env PATH="$bare" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" \
    bash -c 'cd "$1" && shift && exec "$@"' _ "$REPO" "$SCRIPT" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L004"* ]]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "do the thing" ]
}
