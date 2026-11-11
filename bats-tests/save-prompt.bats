#!/usr/bin/env bats
#
# Tests for skills/save-prompt/save-prompt.sh: the transcript mode, the stdin
# mode, the kinds, and the write rules of the prompts/ folder.
#
# The transcripts are fictional. fixtures/save-prompt/transcript.jsonl holds
# one turn of each entry form that the script reads or skips; the other tests
# build small transcripts with jq. A test that fails after a Claude Code
# update says that the transcript form changed.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/save-prompt/save-prompt.sh"
FIXTURE="$PROJECT_ROOT/bats-tests/fixtures/save-prompt/transcript.jsonl"
SESSION_ID="5a7e2c10-3b4d-4e5f-8a9b-0c1d2e3f4a5b"
SEPARATOR="--- Follow-up message in the same turn ---"

setup() {
  TEST_TEMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  FOLDER="$TEST_TEMP_DIR/topic"
  mkdir -p "$FOLDER"
  CFG_DIR="$TEST_TEMP_DIR/config"
  mkdir -p "$CFG_DIR/sessions"
  CFG="$CFG_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
  PROJECTS_DIR="$TEST_TEMP_DIR/projects"
  mkdir -p "$PROJECTS_DIR/-some-project"
  TRANSCRIPT="$PROJECTS_DIR/-some-project/$SESSION_ID.jsonl"
  BIN="$TEST_TEMP_DIR/bin"
  mkdir -p "$BIN"
  STUB_PATH="$BIN:$PATH"
  session_file "$FOLDER"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# session_file <folder> — bind the session to <folder>, as set-work-folder.sh
# does.
session_file() {
  printf '{"version":1,"folder":"%s","session_id":"%s","slug":"t","written_at":"2026-11-10T10:00:00Z"}' \
    "$1" "$SESSION_ID" > "$CFG_DIR/sessions/$SESSION_ID--t.json"
}

# human <text> — print one human message entry.
human() {
  jq -cn --arg t "$1" '{type: "user", origin: {kind: "human"}, message: {role: "user", content: $t}}'
}

# slash <name> <args> — print one human slash command entry, in the form of
# the transcript.
slash() {
  jq -cn --arg n "$1" --arg a "$2" \
    '{type: "user", origin: {kind: "human"}, message: {role: "user", content: ("<command-message>" + $n + "</command-message>\n<command-name>/" + $n + "</command-name>\n<command-args>" + $a + "</command-args>")}}'
}

# queued <text> — print one human message that arrived while a turn ran.
queued() {
  jq -cn --arg t "$1" '{type: "attachment", origin: {kind: "human"}, attachment: {type: "queued_command", prompt: $t, commandMode: "prompt"}}'
}

run_save() {
  run env -u CLAUDE_JOB_DIR -u CLAUDE_CODE_AGENT -u CLAUDE_PID -u CLAUDE_CODE_CHILD_SESSION \
    PATH="$STUB_PATH" MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    SAVE_PROMPT_PROJECTS_DIR="$PROJECTS_DIR" \
    "$SCRIPT" "$@" < /dev/null
}

run_stdin() {
  local input="$1"
  shift
  run env PATH="$STUB_PATH" "$SCRIPT" "$@" < "$input"
}

# clock_stub <stamp>... — each `date +%Y%m%d-%H%M%S` prints the next stamp,
# then repeats the last one; sleep only logs.
clock_stub() {
  printf '%s\n' "$@" > "$TEST_TEMP_DIR/date-queue"
  : > "$TEST_TEMP_DIR/date-last"
  : > "$TEST_TEMP_DIR/sleep-log"
  {
    printf '#!/usr/bin/env bash\nQ=%q\nLAST=%q\nREAL_DATE=%q\n' \
      "$TEST_TEMP_DIR/date-queue" "$TEST_TEMP_DIR/date-last" "$(command -v date)"
    cat <<'STUB'
if [ "$#" -eq 1 ] && [ "$1" = "+%Y%m%d-%H%M%S" ]; then
  if [ -s "$Q" ]; then
    head -n 1 "$Q" > "$LAST"
    tail -n +2 "$Q" > "$Q.next"
    mv "$Q.next" "$Q"
  fi
  cat "$LAST"
  exit 0
fi
exec "$REAL_DATE" "$@"
STUB
  } > "$BIN/date"
  printf '#!/usr/bin/env bash\necho "$*" >> %q\n' "$TEST_TEMP_DIR/sleep-log" > "$BIN/sleep"
  chmod +x "$BIN/date" "$BIN/sleep"
}

# ============================================================================
# Message selection
# ============================================================================

@test "the fixture: a bare /save-prompt saves the message before it, with its queued follow-up" {
  cp "$FIXTURE" "$TRANSCRIPT"
  clock_stub 20261110-100000
  run_save
  [ "$status" -eq 0 ]
  [ "$output" = "$FOLDER/prompts/20261110-100000-saved.txt" ]
  expected="Plan the garden beds:
- tomatoes on the south side
- herbs by the door

$SEPARATOR

Also leave room for tulips."
  [ "$(cat "$output")" = "$expected" ]
}

@test "the fixture: a peer message, a task notification, and a tool result are skipped" {
  cp "$FIXTURE" "$TRANSCRIPT"
  run_save
  [ "$status" -eq 0 ]
  ! grep -q "peer session" "$output"
  ! grep -q "task-notification" "$output"
  ! grep -q "toolu_fixture" "$output"
}

@test "a plain message is saved byte for byte, with one final newline" {
  human "Keep this: it's a \"long\" prompt with \$HOME and \`pwd\`." > "$TRANSCRIPT"
  run_save
  [ "$status" -eq 0 ]
  printf '%s\n' "Keep this: it's a \"long\" prompt with \$HOME and \`pwd\`." | cmp -s - "$output"
}

@test "the newest human message is the one saved" {
  { human "an older prompt"; human "save this prompt verbatim: the newest one"; } > "$TRANSCRIPT"
  run_save
  [ "$status" -eq 0 ]
  [ "$(cat "$output")" = "save this prompt verbatim: the newest one" ]
}

@test "a slash command is rebuilt as /<name> <args>" {
  slash "start-issue" "https://example.com/issues/1 --scratchpad" > "$TRANSCRIPT"
  run_save
  [ "$status" -eq 0 ]
  [ "$(cat "$output")" = "/start-issue https://example.com/issues/1 --scratchpad" ]
}

@test "a slash command with no args is rebuilt as /<name>" {
  slash "finish-issue" "" > "$TRANSCRIPT"
  run_save
  [ "$status" -eq 0 ]
  [ "$(cat "$output")" = "/finish-issue" ]
}

@test "a slash command with multi-line args keeps each line" {
  slash "note" "$(printf 'line one\nline two')" > "$TRANSCRIPT"
  run_save
  [ "$status" -eq 0 ]
  [ "$(cat "$output")" = "$(printf '/note line one\nline two')" ]
}

@test "a bare /save-prompt typed as plain text saves the message before it" {
  { human "the long prompt"; human "  /save-prompt  "; } > "$TRANSCRIPT"
  run_save
  [ "$status" -eq 0 ]
  [ "$(cat "$output")" = "the long prompt" ]
}

@test "/save-prompt with args is not bare, so it is the saved message" {
  { human "an older prompt"; slash "save-prompt" "--kind next"; } > "$TRANSCRIPT"
  run_save
  [ "$status" -eq 0 ]
  [ "$(cat "$output")" = "/save-prompt --kind next" ]
}

@test "a queued follow-up after the newest message follows it under the separator" {
  { human "the prompt"; queued "one more thing"; queued "and another"; } > "$TRANSCRIPT"
  run_save
  [ "$status" -eq 0 ]
  expected="the prompt

$SEPARATOR

one more thing

$SEPARATOR

and another"
  [ "$(cat "$output")" = "$expected" ]
}

@test "a queued message before the saved message is not part of it" {
  { human "an older prompt"; queued "a follow-up of the older prompt"; human "the prompt"; } > "$TRANSCRIPT"
  run_save
  [ "$status" -eq 0 ]
  [ "$(cat "$output")" = "the prompt" ]
}

@test "an array content gives its text blocks, joined with a newline" {
  jq -cn '{type: "user", origin: {kind: "human"}, message: {role: "user", content: [{type: "text", text: "part one"}, {type: "image", source: {}}, {type: "text", text: "part two"}]}}' > "$TRANSCRIPT"
  run_save
  [ "$status" -eq 0 ]
  [ "$(cat "$output")" = "$(printf 'part one\npart two')" ]
}

# ============================================================================
# Kinds
# ============================================================================

@test "the default kind is saved" {
  human "a prompt" > "$TRANSCRIPT"
  clock_stub 20261110-100000
  run_save
  [ "$status" -eq 0 ]
  [ "$output" = "$FOLDER/prompts/20261110-100000-saved.txt" ]
}

@test "each kind names its file: launch, next, and saved" {
  human "a prompt" > "$TRANSCRIPT"
  clock_stub 20261110-100000 20261110-100001 20261110-100002
  for kind in launch next saved; do
    run_save --kind "$kind"
    [ "$status" -eq 0 ]
  done
  [ "$(cd "$FOLDER/prompts" && LC_ALL=C ls -1)" = "20261110-100000-launch.txt
20261110-100001-next.txt
20261110-100002-saved.txt" ]
}

@test "an unknown kind → M001, nothing written" {
  human "a prompt" > "$TRANSCRIPT"
  run_save --kind later
  [ "$status" -eq 1 ]
  [[ "$output" == *"M001"*"unknown kind 'later'"* ]] || false
  [ ! -e "$FOLDER/prompts" ]
}

# ============================================================================
# Refusals of the transcript mode
# ============================================================================

@test "a folder with no prompts/ sub-folder gets one" {
  human "a prompt" > "$TRANSCRIPT"
  [ ! -e "$FOLDER/prompts" ]
  run_save
  [ "$status" -eq 0 ]
  [ -d "$FOLDER/prompts" ]
  [ "$(cd "$FOLDER" && ls -1)" = "prompts" ]
}

@test "no session file → M003 that names /set-work-folder, nothing written" {
  human "a prompt" > "$TRANSCRIPT"
  rm -f "$CFG_DIR/sessions/"*
  run_save
  [ "$status" -eq 1 ]
  [[ "$output" == *"M003"*"/set-work-folder"* ]] || false
  [ ! -e "$FOLDER/prompts" ]
}

@test "no transcript → M004, nothing written" {
  run_save
  [ "$status" -eq 1 ]
  [[ "$output" == *"M004"*"$SESSION_ID.jsonl"* ]] || false
  [ ! -e "$FOLDER/prompts" ]
}

@test "a transcript with no human type: user entry → M005 that says the form can have changed" {
  {
    jq -cn '{type: "user", message: {role: "user", content: "no origin"}}'
    jq -cn '{type: "user", origin: {kind: "peer"}, message: {role: "user", content: "a peer"}}'
    queued "a queued message alone"
  } > "$TRANSCRIPT"
  run_save
  [ "$status" -eq 1 ]
  [[ "$output" == *"M005"*"transcript form can have changed"* ]] || false
  [ ! -e "$FOLDER/prompts" ]
}

@test "a bare /save-prompt with no message before it → M005, nothing written" {
  slash "save-prompt" "" > "$TRANSCRIPT"
  run_save
  [ "$status" -eq 1 ]
  [[ "$output" == *"M005"*"bare /save-prompt"* ]] || false
  [ ! -e "$FOLDER/prompts" ]
}

@test "transcript mode takes no folder argument → M001" {
  human "a prompt" > "$TRANSCRIPT"
  run_save "$FOLDER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"M001"*"--from stdin"* ]] || false
}

@test "no jq on PATH in transcript mode → M003" {
  human "a prompt" > "$TRANSCRIPT"
  STUB_PATH="$(_stub_path_without "$TEST_TEMP_DIR/nojq" jq)"
  run_save
  [ "$status" -eq 1 ]
  [[ "$output" == *"M003"*"jq not found"* ]] || false
}

# ============================================================================
# Writes
# ============================================================================

@test "a repeat of the newest file of the same kind writes nothing and prints the Repeat: line" {
  human "a prompt" > "$TRANSCRIPT"
  clock_stub 20261110-100000 20261110-100001
  run_save
  [ "$status" -eq 0 ]
  first="$output"
  run_save
  [ "$status" -eq 0 ]
  [ "$output" = "Repeat: the prompt matches $first, so no new file was written." ]
  [ "$(ls -1 "$FOLDER/prompts" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "the same text in another kind is not a repeat" {
  human "a prompt" > "$TRANSCRIPT"
  clock_stub 20261110-100000 20261110-100001
  run_save --kind saved
  run_save --kind next
  [ "$status" -eq 0 ]
  [ "$output" = "$FOLDER/prompts/20261110-100001-next.txt" ]
}

@test "a taken stamp waits for the next second" {
  human "a prompt" > "$TRANSCRIPT"
  mkdir -p "$FOLDER/prompts"
  printf 'other\n' > "$FOLDER/prompts/20261110-100000-next.txt"
  clock_stub 20261110-100000 20261110-100001
  run_save
  [ "$status" -eq 0 ]
  [ "$output" = "$FOLDER/prompts/20261110-100001-saved.txt" ]
  [ "$(wc -l < "$TEST_TEMP_DIR/sleep-log" | tr -d ' ')" -eq 1 ]
  [ "$(cat "$FOLDER/prompts/20261110-100000-next.txt")" = "other" ]
}

@test "a clock that stays on a taken second → M006 after three tries, nothing written" {
  human "a prompt" > "$TRANSCRIPT"
  mkdir -p "$FOLDER/prompts"
  printf 'other\n' > "$FOLDER/prompts/20261110-100000-next.txt"
  clock_stub 20261110-100000
  run_save
  [ "$status" -eq 1 ]
  [[ "$output" == *"M006"*"no free name"* ]] || false
  [ "$(wc -l < "$TEST_TEMP_DIR/sleep-log" | tr -d ' ')" -eq 2 ]
  [ "$(ls -1 "$FOLDER/prompts")" = "20261110-100000-next.txt" ]
}

# ============================================================================
# Stdin mode
# ============================================================================

@test "stdin mode saves the bytes of standard input in the folder" {
  printf 'line one\n\nline three with $HOME\n' > "$TEST_TEMP_DIR/in.txt"
  clock_stub 20261110-100000
  run_stdin "$TEST_TEMP_DIR/in.txt" --from stdin --kind next "$FOLDER"
  [ "$status" -eq 0 ]
  [ "$output" = "$FOLDER/prompts/20261110-100000-next.txt" ]
  cmp -s "$TEST_TEMP_DIR/in.txt" "$output"
}

@test "stdin mode needs no jq and no session" {
  printf 'a prompt\n' > "$TEST_TEMP_DIR/in.txt"
  nojq="$(_stub_path_without "$TEST_TEMP_DIR/nojq" jq)"
  run env -i PATH="$nojq" HOME="$TEST_TEMP_DIR" "$SCRIPT" --from stdin "$FOLDER" < "$TEST_TEMP_DIR/in.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == "$FOLDER/prompts/"*"-saved.txt" ]] || false
}

@test "stdin mode with empty input → M001, nothing written" {
  printf '  \n\n' > "$TEST_TEMP_DIR/in.txt"
  run_stdin "$TEST_TEMP_DIR/in.txt" --from stdin "$FOLDER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"M001"*"empty"* ]] || false
  [ ! -e "$FOLDER/prompts" ]
}

@test "stdin mode with a relative or missing folder → M002" {
  printf 'a prompt\n' > "$TEST_TEMP_DIR/in.txt"
  run_stdin "$TEST_TEMP_DIR/in.txt" --from stdin topic
  [ "$status" -eq 1 ]
  [[ "$output" == *"M002"*"not an absolute path"* ]] || false
  run_stdin "$TEST_TEMP_DIR/in.txt" --from stdin "$TEST_TEMP_DIR/missing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"M002"*"not an existing directory"* ]] || false
}

@test "stdin mode with no folder → M001" {
  printf 'a prompt\n' > "$TEST_TEMP_DIR/in.txt"
  run_stdin "$TEST_TEMP_DIR/in.txt" --from stdin
  [ "$status" -eq 1 ]
  [[ "$output" == *"M001"* ]] || false
}

@test "an unknown mode → M001" {
  run_save --from clipboard
  [ "$status" -eq 1 ]
  [[ "$output" == *"M001"*"unknown mode 'clipboard'"* ]] || false
}

# ============================================================================
# The launch kind and the old names (A099)
# ============================================================================

@test "launch: with no launch file in prompts/, the repeat check reads the newest old name by stamp" {
  printf 'the first prompt\n' > "$FOLDER/prompt-new-agent-launch.txt"
  printf 'the newest prompt\n' > "$FOLDER/prompt-new-agent-launch.txt.update-20260930-100000.txt"
  printf 'the newest prompt\n' > "$TEST_TEMP_DIR/in.txt"
  run_stdin "$TEST_TEMP_DIR/in.txt" --from stdin --kind launch "$FOLDER"
  [ "$status" -eq 0 ]
  [ "$output" = "Repeat: the prompt matches $FOLDER/prompt-new-agent-launch.txt.update-20260930-100000.txt, so no new file was written." ]
}

@test "saved: the old launch names are never a repeat of another kind" {
  printf 'the first prompt\n' > "$FOLDER/prompt-new-agent-launch.txt"
  printf 'the first prompt\n' > "$TEST_TEMP_DIR/in.txt"
  clock_stub 20261110-100000
  run_stdin "$TEST_TEMP_DIR/in.txt" --from stdin "$FOLDER"
  [ "$status" -eq 0 ]
  [ "$output" = "$FOLDER/prompts/20261110-100000-saved.txt" ]
}

@test "--help prints the usage" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: save-prompt.sh"* ]] || false
}
