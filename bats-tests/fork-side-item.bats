#!/usr/bin/env bats
#
# Tests for skills/fork-side-item/fork-side-item.sh — the side folder name, the
# refusal of an existing side folder, the list mode, and the hand-off to
# launch-agent.sh.
#
# `claude` is replaced by a stub first on PATH that records its arguments and
# prints the status line `claude --bg` prints, so no test starts a real
# session. Every run points MY_CLAUDE_SKILLS_CONFIG at a temp settings file and
# has no session id, so the depth records and the topic root stay in the temp
# directory.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/fork-side-item/fork-side-item.sh"

claude_stub() {
  cat > "$1/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$ARGS_FILE"
printf 'backgrounded · a1b2c3d4 · %s\n' "$3"
printf '  claude attach a1b2c3d4    open in this terminal\n'
STUB
  chmod +x "$1/claude"
}

setup() {
  TEST_TEMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  BIN="$TEST_TEMP_DIR/bin"
  mkdir -p "$BIN"
  claude_stub "$BIN"
  ARGS_FILE="$TEST_TEMP_DIR/claude-args.txt"
  export ARGS_FILE
  STUB_PATH="$BIN:$PATH"
  REPO="$TEST_TEMP_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
}

# run_fork <dir> <stdin text> <args...> — run the script from <dir> with
# <stdin text> on standard input.
run_fork() {
  local dir="$1" input="$2"
  shift 2
  run --separate-stderr env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_JOB_DIR \
    -u CLAUDE_CODE_CHILD_SESSION PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && input="$1" && shift && printf "%s" "$input" | "$@"' \
    _ "$dir" "$input" "$SCRIPT" "$@"
}

@test "a fork with no hook creates side-<slug>, saves the prompt, and starts the worker with --bg" {
  run_fork "$REPO" "check the claim" fork "The README links a dead page"
  [ "$status" -eq 0 ]
  local folder="$REPO/side-the-readme-links-a-dead-page"
  [ -d "$folder" ]
  [ "$(cat "$folder/prompt-new-agent-launch.txt")" = "check the claim" ]
  [[ "$(cat "$ARGS_FILE")" == "--bg --name side-the-readme-links-a-dead-page "* ]]
  [[ "$output" == *"Folder: $folder"* ]]
  [[ "$output" == *"Job: a1b2c3d4"* ]]
  [ "${lines[${#lines[@]}-1]}" = "side.forked: $folder" ]
}

@test "the slug is cut at 50 characters" {
  local claim="one two three four five six seven eight nine ten eleven twelve"
  run_fork "$REPO" "prompt" fork "$claim"
  [ "$status" -eq 0 ]
  local slug
  slug="$(printf '%s' "${lines[${#lines[@]}-1]}" | sed 's#.*/side-##')"
  [ "${#slug}" -le 50 ]
  [ "$slug" = "one-two-three-four-five-six-seven-eight-nine-ten-e" ]
}

@test "an existing side folder → F002 with its state open, and no launch" {
  mkdir -p "$REPO/side-a-claim"
  run_fork "$REPO" "prompt" fork "a claim"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"F002"* ]]
  [[ "$stderr" == *"state: open"* ]]
  [[ "$stderr" == *"run /resume-agent $REPO/side-a-claim to wake it"* ]]
  [ ! -e "$ARGS_FILE" ]
}

@test "an existing closed side folder → F002 with its outcome" {
  mkdir -p "$REPO/side-a-claim"
  printf 'ticket\thttps://example.com/1\n' > "$REPO/side-a-claim/side-outcome.txt"
  run_fork "$REPO" "prompt" fork "a claim"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"state: ticket"* ]]
  [[ "$stderr" != *"/resume-agent"* ]]
}

@test "the side folder lands under launchAgentDefaultFolder when it is set" {
  mkdir -p "$TEST_TEMP_DIR/topics"
  printf '{"launchAgentDefaultFolder":"%s"}' "$TEST_TEMP_DIR/topics" > "$CFG"
  run_fork "$REPO" "prompt" fork "a claim"
  [ "$status" -eq 0 ]
  [ -d "$TEST_TEMP_DIR/topics/side-a-claim" ]
  [ "${lines[${#lines[@]}-1]}" = "side.forked: $TEST_TEMP_DIR/topics/side-a-claim" ]
}

@test "a launch that launch-agent.sh refuses → its error, then F004" {
  printf '%s' '{"launchAgentMaxDepth": 0}' > "$CFG"
  run_fork "$REPO" "prompt" fork "a claim"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"L006"* ]]
  [[ "$stderr" == *"F004"* ]]
  [ ! -e "$REPO/side-a-claim" ]
}

@test "list prints each side folder with its state, and nothing else" {
  mkdir -p "$REPO/side-open-one" "$REPO/side-closed-one" "$REPO/not-a-side"
  printf 'drop\tthe claim is false\n' > "$REPO/side-closed-one/side-outcome.txt"
  : > "$REPO/side-a-file"
  run_fork "$REPO" "" list
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO/side-closed-one	drop
$REPO/side-open-one	open" ]
  [[ "$stderr" == *"run /resume-agent <folder> to wake it"* ]]
}

@test "list with only closed side folders prints no wake hint" {
  mkdir -p "$REPO/side-closed-one"
  printf 'drop\tthe claim is false\n' > "$REPO/side-closed-one/side-outcome.txt"
  run_fork "$REPO" "" list
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "list with no side folder prints nothing" {
  run_fork "$REPO" "" list
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an empty prompt → F001, nothing created" {
  run_fork "$REPO" "   " fork "a claim"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"F001"* ]]
  [ ! -e "$REPO/side-a-claim" ]
}

@test "an empty claim → F001" {
  run_fork "$REPO" "prompt" fork "  "
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"F001"* ]]
}

@test "no mode, an unknown mode, and extra arguments → F001" {
  run_fork "$REPO" "prompt"
  [[ "$stderr" == *"F001"* ]]
  run_fork "$REPO" "prompt" launch "a claim"
  [[ "$stderr" == *"F001"* ]]
  run_fork "$REPO" "prompt" fork "a claim" extra
  [[ "$stderr" == *"F001"* ]]
  run_fork "$REPO" "" list extra
  [[ "$stderr" == *"F001"* ]]
}

@test "--help prints the usage" {
  run_fork "$REPO" "" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"fork-side-item.sh list"* ]]
}

@test "no repository and no setting → F003" {
  mkdir -p "$TEST_TEMP_DIR/plain"
  run_fork "$TEST_TEMP_DIR/plain" "prompt" fork "a claim"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"F003"* ]]
}

@test "a relative launchAgentDefaultFolder → F003" {
  printf '%s' '{"launchAgentDefaultFolder":"topics"}' > "$CFG"
  run_fork "$REPO" "" list
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"F003"* ]]
}
