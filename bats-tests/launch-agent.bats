#!/usr/bin/env bats
#
# Tests for skills/launch-agent/launch-agent.sh — folder resolution, the
# near-match slug guard, prompt resolution and saving, preamble composition,
# and dispatch.
#
# `claude` is replaced by a stub first on PATH that records its arguments and
# its working directory, so every dispatch assertion is made without starting
# a real background session; the tests that reach it pass --bg. The in-session
# tests start no session at all: they point MY_CLAUDE_SKILLS_CONFIG at a temp
# settings file, which puts the sessions directory beside it, so a developer's
# real ~/.my-claude-skills/sessions/ is never touched.
#
# Every run points MY_CLAUDE_SKILLS_CONFIG at the temp settings file, because
# the script reads launchAgentDefaultFolder from it, and a developer's own
# value would move every slug. Every run also reads standard input from
# /dev/null unless a test feeds it, so no run waits on a terminal and no run
# reads a prompt nobody gave it.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/launch-agent/launch-agent.sh"
RESOLVER="$PROJECT_ROOT/skills/issue-context/get-issue-folder-path.sh"

SESSION_ID="9c1f3e70-2a44-4c8e-9d61-5b0f7a2c8d13"

# claude_stub <dir> — write a stub `claude` that records "$*" to $ARGS_FILE and
# its working directory to $CWD_FILE, then prints what `claude --bg` prints: a
# status line carrying the job id between two `·` separators, then four hint
# lines. The layout is a copy of one real run of Claude Code 2.1.289, with the
# id replaced, so the parse is tested against the shape it meets, not against a
# bare id. Set STUB_FAIL=1 in the environment to make it exit non-zero instead,
# STUB_SILENT=1 to make it succeed while printing nothing, and STUB_OUTPUT to
# make it succeed while printing that text in place of the real layout.
# `claude agents --json [--all]` is the list that folder-sessions.sh reads: it
# prints $AGENTS_FILE when that file is not empty, else an empty list, and
# fails with STUB_AGENTS_FAIL=1. It records nothing.
claude_stub() {
  cat > "$1/claude" <<'STUB'
#!/usr/bin/env bash
if [ "${1-} ${2-}" = "agents --json" ]; then
  [ "${STUB_AGENTS_FAIL:-0}" = "1" ] && exit 3
  if [ -n "${AGENTS_FILE:-}" ] && [ -s "$AGENTS_FILE" ]; then cat "$AGENTS_FILE"; else printf '[]'; fi
  exit 0
fi
[ -z "${ARGS_FILE:-}" ] || printf '%s\n' "$*" > "$ARGS_FILE"
[ -z "${CWD_FILE:-}" ] || pwd > "$CWD_FILE"
if [ "${STUB_FAIL:-0}" = "1" ]; then
  echo "launch refused" >&2
  exit 7
fi
[ "${STUB_SILENT:-0}" = "1" ] && exit 0
if [ -n "${STUB_OUTPUT:-}" ]; then
  printf '%b\n' "$STUB_OUTPUT"
  exit 0
fi
# --bg --name <name> <prompt>, so the name is the third argument.
printf 'backgrounded · a1b2c3d4 · %s\n' "$3"
printf '  claude agents             list sessions\n'
printf '  claude attach a1b2c3d4    open in this terminal\n'
printf '  claude logs a1b2c3d4      show recent output\n'
printf '  claude stop a1b2c3d4      stop this session\n'
STUB
  chmod +x "$1/claude"
}

# clock_stub <stamp>... — put `date` and `sleep` stubs first on PATH, so a test
# decides each stamp the script reads and no test waits a real second.
#
# `date +%Y%m%d-%H%M%S` prints the next stamp from $DATE_QUEUE and logs the
# call to $DATE_LOG. With the queue empty it prints the last stamp again,
# which is a clock that stays on one second. Every other `date` call goes to
# the real tool, because set-work-folder.sh reads the clock in its own format
# during adoption, and a stub that answered it would break the default mode.
# `sleep` logs each call to $SLEEP_LOG and returns at once.
clock_stub() {
  DATE_QUEUE="$TEST_TEMP_DIR/date-queue.txt"
  DATE_LAST="$TEST_TEMP_DIR/date-last.txt"
  DATE_LOG="$TEST_TEMP_DIR/date-log.txt"
  SLEEP_LOG="$TEST_TEMP_DIR/sleep-log.txt"
  export DATE_QUEUE DATE_LAST DATE_LOG SLEEP_LOG
  printf '%s\n' "$@" > "$DATE_QUEUE"
  : > "$DATE_LAST"
  : > "$DATE_LOG"
  : > "$SLEEP_LOG"
  {
    printf '#!/usr/bin/env bash\nREAL_DATE=%q\n' "$(command -v date)"
    cat <<'STUB'
if [ "$#" -eq 1 ] && [ "$1" = "+%Y%m%d-%H%M%S" ]; then
  echo call >> "$DATE_LOG"
  if [ -s "$DATE_QUEUE" ]; then
    head -n 1 "$DATE_QUEUE" > "$DATE_LAST"
    tail -n +2 "$DATE_QUEUE" > "$DATE_QUEUE.next"
    mv "$DATE_QUEUE.next" "$DATE_QUEUE"
  fi
  cat "$DATE_LAST"
  exit 0
fi
exec "$REAL_DATE" "$@"
STUB
  } > "$BIN/date"
  cat > "$BIN/sleep" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$SLEEP_LOG"
STUB
  chmod +x "$BIN/date" "$BIN/sleep"
}

# _prompt_files <dir> — print the prompt file names in <dir>, one per line, in
# byte order.
_prompt_files() {
  (cd "$1" && LC_ALL=C ls -1 | grep '^prompt-new-agent-launch' || true)
}

# _contains <haystack> <needle> — fail the test when <needle> is not a literal
# substring of <haystack>.
#
# A bare `[[ ... ]]` that is not the last command in a test does not fail that
# test: bash fires no ERR trap for a conditional compound command, and the ERR
# trap is what bats fails on. A function call is a simple command, so this one
# fails where a bare [[ ]] silently passes. The tests below that assert exact
# shell quoting use it, because a quoting assertion that cannot fail is worth
# nothing.
_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  printf 'expected to find:\n  %s\n\nin:\n  %s\n' "$2" "$1" >&2
  return 1
}

# _lacks <haystack> <needle> — fail the test when <needle> is a literal
# substring of <haystack>. The negative of _contains, for the same reason.
_lacks() {
  case "$1" in
    *"$2"*)
      printf 'expected not to find:\n  %s\n\nin:\n  %s\n' "$2" "$1" >&2
      return 1
      ;;
  esac
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
  AGENTS_FILE="$TEST_TEMP_DIR/agents.json"
  : > "$AGENTS_FILE"
  export ARGS_FILE CWD_FILE AGENTS_FILE
  STUB_PATH="$BIN:$PATH"

  # A repository to launch from. `git init` alone is enough: every path this
  # script takes asks git only for --show-toplevel and --git-common-dir.
  REPO="$TEST_TEMP_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q

  # The default mode writes a session override through set-work-folder.sh,
  # which derives the sessions directory from the settings file's own
  # directory.
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
  SESSIONS_DIR="$TEST_TEMP_DIR/sessions"

  # A floor under every run, including a test that builds its own env line:
  # the fixture settings file, and no live session. Without it, a run that
  # forgets MY_CLAUDE_SKILLS_CONFIG reads the developer's own
  # launchAgentDefaultFolder, and a run in the default mode adopts the folder
  # for the developer's live session. The helpers still set both explicitly.
  export MY_CLAUDE_SKILLS_CONFIG="$CFG"
  unset CLAUDE_CODE_SESSION_ID CLAUDE_JOB_DIR CLAUDE_CODE_AGENT CLAUDE_PID \
    CLAUDE_CODE_CHILD_SESSION
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# run_in <dir> <args...> — run the script from <dir> with the stubbed PATH, the
# temp settings file, and no session id, so the default mode refuses and the
# tests that reach dispatch pass --bg.
run_in() {
  local dir="$1"
  shift
  run env -u CLAUDE_CODE_SESSION_ID \
    PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$dir" "$SCRIPT" "$@"
}

# run_here <dir> <args...> — run the script from <dir> as a Claude Code session
# owning SESSION_ID, with the settings file in the temp directory.
#
# Every other CLAUDE_* variable set-work-folder.sh reads is unset first. A bats
# run inherits the environment of whoever started it, and when that is a Claude
# Code session the real id, job directory and pid are all set, so without -u
# these tests would write into the developer's live session rather than the
# fixture.
run_here() {
  local dir="$1"
  shift
  run env -u CLAUDE_JOB_DIR -u CLAUDE_CODE_AGENT -u CLAUDE_PID \
    -u CLAUDE_CODE_CHILD_SESSION \
    PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$dir" "$SCRIPT" "$@"
}

# run_here_stdin <dir> <stdin-file> <args...> — run_here, with <stdin-file> on
# standard input in place of /dev/null.
run_here_stdin() {
  local dir="$1" input="$2"
  shift 2
  run env -u CLAUDE_JOB_DIR -u CLAUDE_CODE_AGENT -u CLAUDE_PID \
    -u CLAUDE_CODE_CHILD_SESSION \
    PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    bash -c 'cd "$1" && input="$2" && shift 2 && exec "$@" < "$input"' _ "$dir" "$input" "$SCRIPT" "$@"
}

# set_default_folder <value> — write <value> as launchAgentDefaultFolder into
# the temp settings file, JSON-encoded by jq so any value survives.
set_default_folder() {
  jq -n --arg v "$1" '{launchAgentDefaultFolder: $v}' > "$CFG"
}

# ============================================================================
# Usage
# ============================================================================

@test "--help prints usage and exits 0" {
  run_in "$REPO" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: launch-agent.sh"* ]] || false
}

@test "no arguments → L001, usage on stderr" {
  run_in "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]] || false
  [[ "$output" == *"a folder is required"* ]] || false
}

@test "folder but no prompt → L001" {
  run_in "$REPO" topic
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]] || false
  [[ "$output" == *"a task prompt is required"* ]] || false
}

@test "an unknown flag before the folder → L001, nothing created" {
  run_in "$REPO" --bogus thing "do it"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]] || false
  [[ "$output" == *"unknown flag '--bogus'"* ]] || false
  [ ! -d "$REPO/thing" ]
}

@test "--name → L001 saying it was removed, nothing created" {
  run_here "$REPO" --name thing my-topic "do it"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]] || false
  [[ "$output" == *"--name was removed"* ]] || false
  [ ! -d "$REPO/my-topic" ]
}

@test "--here → L001 saying it was removed, nothing created" {
  run_here "$REPO" --here my-topic "do it"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]] || false
  [[ "$output" == *"--here was removed"* ]] || false
  [ ! -d "$REPO/my-topic" ]
}

@test "the old order <folder> --bg → L001 with the new form, and no agent starts" {
  run_in "$REPO" my-topic --bg "do it"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]] || false
  [[ "$output" == *"launch-agent.sh --bg my-topic"* ]] || false
  [ ! -e "$ARGS_FILE" ]
  [ ! -d "$REPO/my-topic" ]
}

@test "the old order <folder> --take-over → L001 with the new form, nothing created" {
  run_here "$REPO" my-topic --take-over "do it"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]] || false
  [[ "$output" == *"launch-agent.sh --take-over my-topic"* ]] || false
  [ ! -d "$REPO/my-topic" ]
}

@test "folder, no prompt argument, and empty stdin → L001" {
  : > "$TEST_TEMP_DIR/empty.txt"
  run_here_stdin "$REPO" "$TEST_TEMP_DIR/empty.txt" my-topic
  [ "$status" -eq 1 ]
  [[ "$output" == *"a task prompt is required"* ]] || false
  [ ! -d "$REPO/my-topic" ]
}

# ============================================================================
# Folder resolution
# ============================================================================

@test "slug resolves to <repo-root>/<slug>, not into .claude-work" {
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Folder: $REPO/my-topic"* ]] || false
  [ -d "$REPO/my-topic" ]
  [ ! -d "$REPO/.claude-work/my-topic" ]
}

@test "slug resolves against the main checkout when run from a subdirectory" {
  mkdir -p "$REPO/src/deep"
  run_in "$REPO/src/deep" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Folder: $REPO/my-topic"* ]] || false
}

@test "absolute path is used as given, outside any repository" {
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_in "$REPO" --bg "$target" "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Folder: $target"* ]] || false
  [ -d "$target" ]
}

@test "absolute path with a trailing slash still names the job after the basename" {
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_in "$REPO" --bg "$target/" "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: topic"* ]] || false
}

@test "existing folder is reused, not refused" {
  mkdir -p "$REPO/my-topic"
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Folder: $REPO/my-topic"* ]] || false
}

@test "folder path that exists as a regular file → L002, nothing written" {
  : > "$TEST_TEMP_DIR/afile"
  run_in "$REPO" --bg "$TEST_TEMP_DIR/afile" "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]] || false
  [[ "$output" == *"is not a directory"* ]] || false
  [ ! -f "$ARGS_FILE" ]
}

@test "slug outside a git repository → L002 asking for an absolute path" {
  outside="$TEST_TEMP_DIR/no-repo"
  mkdir -p "$outside"
  run_in "$outside" --bg my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]] || false
  [[ "$output" == *"pass an absolute path instead"* ]] || false
  [ ! -d "$outside/my-topic" ]
}

@test "slug containing a separator → L002, nothing created" {
  run_in "$REPO" --bg team/onboarding "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]] || false
  [[ "$output" == *"is not a single path component"* ]] || false
  [ ! -d "$REPO/team" ]
}

@test "slug of .. → L002, nothing created outside the root" {
  run_in "$REPO" --bg .. "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]] || false
  [[ "$output" == *"is not a topic name"* ]] || false
}

@test "slug naming a symlink to a directory resolves to the link's target" {
  outside="$TEST_TEMP_DIR/outside"
  mkdir -p "$outside"
  ln -s "$outside" "$REPO/linked"
  run_in "$REPO" --bg linked "do the thing"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Folder: $outside" ]
  [ "$(cat "$outside/prompt-new-agent-launch.txt")" = "do the thing" ]
}

# ============================================================================
# The launchAgentDefaultFolder setting
# ============================================================================

@test "slug with the setting set lands under that directory, not in the launching repository" {
  topics="$TEST_TEMP_DIR/topics"
  mkdir -p "$topics"
  set_default_folder "$topics"
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Folder: $topics/my-topic" ]
  [ ! -d "$REPO/my-topic" ]
}

@test "the setting also serves a launch from outside any repository" {
  topics="$TEST_TEMP_DIR/topics"
  outside="$TEST_TEMP_DIR/no-repo"
  mkdir -p "$topics" "$outside"
  set_default_folder "$topics"
  run_here "$outside" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ -d "$topics/my-topic" ]
}

@test "the setting naming a missing directory → L002 naming the key and value, nothing written" {
  set_default_folder "$TEST_TEMP_DIR/not-there"
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]] || false
  [[ "$output" == *"launchAgentDefaultFolder"* ]] || false
  [[ "$output" == *"'$TEST_TEMP_DIR/not-there'"* ]] || false
  [[ "$output" == *"not an existing directory"* ]] || false
  [ ! -d "$TEST_TEMP_DIR/not-there" ]
  [ ! -d "$REPO/my-topic" ]
}

@test "the setting holding a relative path → L002, nothing written" {
  set_default_folder "topics"
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]] || false
  [[ "$output" == *"'topics', which is not an absolute path"* ]] || false
  [ ! -d "$REPO/topics" ]
  [ ! -d "$REPO/my-topic" ]
}

@test "the setting is not expanded: a leading ~ is a relative path" {
  set_default_folder "~/topics"
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'~/topics', which is not an absolute path"* ]] || false
}

@test "the near-match guard runs against the setting's directory" {
  topics="$TEST_TEMP_DIR/topics"
  mkdir -p "$topics/my_topic"
  set_default_folder "$topics"
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nearly matches the existing 'my_topic' in $topics"* ]] || false
  [ ! -d "$topics/my-topic" ]
}

@test "an absolute folder wins over the setting" {
  topics="$TEST_TEMP_DIR/topics"
  mkdir -p "$topics"
  set_default_folder "$topics"
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_here "$REPO" "$target" "do the thing"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Folder: $target" ]
  [ ! -d "$topics/topic" ]
}

@test "the setting with a trailing slash resolves the slug as if the slash were absent" {
  topics="$TEST_TEMP_DIR/topics"
  mkdir -p "$topics"
  set_default_folder "$topics/"
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Folder: $topics/my-topic" ]
}

@test "a malformed settings file → L002 for a slug, nothing written in the repository" {
  printf '%s' '{"launchAgentDefaultFolder":' > "$CFG"
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]] || false
  [[ "$output" == *"$CFG could not be read"* ]] || false
  [ ! -d "$REPO/my-topic" ]
  [ ! -f "$ARGS_FILE" ]
}

@test "an unreadable settings file → L002 for a slug, nothing written in the repository" {
  _require_enforced_permission_bits
  set_default_folder "$TEST_TEMP_DIR/topics"
  chmod 000 "$CFG"
  run_in "$REPO" --bg my-topic "do the thing"
  chmod 644 "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]] || false
  [[ "$output" == *"could not be read"* ]] || false
  [ ! -d "$REPO/my-topic" ]
}

@test "a malformed settings file does not block an absolute folder" {
  printf '%s' '{"launchAgentDefaultFolder":' > "$CFG"
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_in "$REPO" --bg "$target" "do the thing"
  [ "$status" -eq 0 ]
  # The loader's warning comes first in the merged output, so match the line
  # anywhere rather than at lines[0].
  [[ "$output" == *"Folder: $target"* ]] || false
  [ -f "$target/prompt-new-agent-launch.txt" ]
}

@test "an absolute folder is used even when the setting names a missing directory" {
  set_default_folder "$TEST_TEMP_DIR/not-there"
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_here "$REPO" "$target" "do the thing"
  [ "$status" -eq 0 ]
  [ -d "$target" ]
}

# ============================================================================
# The near-match slug guard
# ============================================================================

@test "slug that normalizes onto an existing sibling → L002 naming the sibling" {
  mkdir -p "$REPO/agent_launch_skill"
  run_in "$REPO" --bg agent-launch-skill "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]] || false
  [[ "$output" == *"nearly matches the existing 'agent_launch_skill'"* ]] || false
  [ ! -d "$REPO/agent-launch-skill" ]
}

@test "case-only difference is a near match too" {
  mkdir -p "$REPO/MyTopic"
  run_in "$REPO" --bg mytopic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nearly matches the existing 'MyTopic'"* ]] || false
}

@test "exact match is not a refusal: a second agent joins an existing topic" {
  mkdir -p "$REPO/my-topic"
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
}

@test "a regular file that normalizes onto the slug does not refuse it" {
  : > "$REPO/my_topic"
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ -d "$REPO/my-topic" ]
}

@test "an absolute path skips the guard, which is the way past a refusal" {
  mkdir -p "$REPO/agent_launch_skill"
  run_in "$REPO" --bg "$REPO/agent-launch-skill" "do the thing"
  [ "$status" -eq 0 ]
  [ -d "$REPO/agent-launch-skill" ]
}

# ============================================================================
# Prompt resolution
# ============================================================================

@test "multi-word prompt is written verbatim" {
  run_in "$REPO" --bg my-topic "do the thing" "and then another"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "do the thing and then another" ]
}

@test "single token naming a readable file contributes that file's content" {
  printf 'line one\nline two\n' > "$TEST_TEMP_DIR/prompt.txt"
  run_in "$REPO" --bg my-topic "$TEST_TEMP_DIR/prompt.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "$(printf 'line one\nline two')" ]
  [[ "$(cat "$ARGS_FILE")" == *"line two"* ]] || false
}

@test "path-shaped single token naming nothing → L003, nothing written" {
  run_in "$REPO" --bg my-topic ./plans/lanch-prompt.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"L003"* ]] || false
  [[ "$output" == *"looks like a file path but names no readable file"* ]] || false
  [ ! -d "$REPO/my-topic" ]
  [ ! -f "$ARGS_FILE" ]
}

@test "unreadable file at a path-shaped token → L003 rather than a literal prompt" {
  _require_enforced_permission_bits
  printf 'secret\n' > "$TEST_TEMP_DIR/prompt.md"
  chmod 000 "$TEST_TEMP_DIR/prompt.md"
  run_in "$REPO" --bg my-topic "$TEST_TEMP_DIR/prompt.md"
  chmod 644 "$TEST_TEMP_DIR/prompt.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L003"* ]] || false
}

@test "a prompt on stdin is saved byte for byte" {
  cat > "$TEST_TEMP_DIR/stdin.txt" <<'PROMPT'
Look at https://example.com/a?b=1&c=2 and /note what you find.
Don't touch the user's "config" — ~/.claude/x, $HOME, `pwd`, and \n stay as typed.
PROMPT
  run_here_stdin "$REPO" "$TEST_TEMP_DIR/stdin.txt" my-topic
  [ "$status" -eq 0 ]
  cmp "$TEST_TEMP_DIR/stdin.txt" "$REPO/my-topic/prompt-new-agent-launch.txt"
}

@test "a prompt on stdin reaches the agent with --bg" {
  printf '%s\n' "Fix /note handling in skills/x.sh" > "$TEST_TEMP_DIR/stdin.txt"
  run env -u CLAUDE_CODE_SESSION_ID PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" \
    CWD_FILE="$CWD_FILE" MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < "$0"' "$TEST_TEMP_DIR/stdin.txt" "$REPO" "$SCRIPT" --bg my-topic
  [ "$status" -eq 0 ]
  _contains "$(cat "$ARGS_FILE")" "Fix /note handling in skills/x.sh"
}

@test "a prompt argument wins over stdin" {
  printf 'from stdin\n' > "$TEST_TEMP_DIR/stdin.txt"
  run_here_stdin "$REPO" "$TEST_TEMP_DIR/stdin.txt" my-topic "from the argument"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "from the argument" ]
}

@test "a single argument with whitespace is prompt text, even with a URL and a slash command" {
  run_here "$REPO" my-topic "Look at https://x/y and /note it"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "Look at https://x/y and /note it" ]
}

@test "a single argument with whitespace is not read as a file, even when one exists by that name" {
  mkdir -p "$REPO/a b"
  printf 'file content\n' > "$REPO/a b/c.txt"
  run_here "$REPO" my-topic "a b/c.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "a b/c.txt" ]
}

@test "one-word literal prompt that is not path-shaped passes through" {
  run_in "$REPO" --bg my-topic triage
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "triage" ]
}

@test "empty prompt → L003, nothing created" {
  run_in "$REPO" --bg my-topic ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"L003"* ]] || false
  [ ! -d "$REPO/my-topic" ]
}

# ============================================================================
# Later launches: the first prompt stays, each later prompt is a new file
# ============================================================================

@test "a later launch leaves the first prompt's bytes and modification time as they were" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  touch -t 202001021530.45 "$REPO/my-topic/prompt-new-agent-launch.txt" "$TEST_TEMP_DIR/ref"
  clock_stub 20260930-120000
  run_in "$REPO" --bg my-topic "a later prompt"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "the first prompt" ]
  [ ! "$REPO/my-topic/prompt-new-agent-launch.txt" -nt "$TEST_TEMP_DIR/ref" ]
  [ ! "$TEST_TEMP_DIR/ref" -nt "$REPO/my-topic/prompt-new-agent-launch.txt" ]
}

@test "a later launch writes an update file named after the launch time" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  clock_stub 20260930-120000
  run_in "$REPO" --bg my-topic "a later prompt"
  [ "$status" -eq 0 ]
  update="$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt"
  printf 'a later prompt\n' | cmp -s - "$update"
  _contains "$output" "Prompt: $update"
  _lacks "$output" "Repeat:"
}

@test "a second later launch adds a second update file and changes neither earlier file" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  clock_stub 20260930-120000 20260930-130000
  run_in "$REPO" --bg my-topic "the second prompt"
  [ "$status" -eq 0 ]
  run_in "$REPO" --bg my-topic "the third prompt"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "the first prompt" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt")" = "the second prompt" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-130000.txt")" = "the third prompt" ]
}

@test "a taken update name waits one second and takes the next stamp" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'a launch in the same second\n' > "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt"
  clock_stub 20260930-120000 20260930-120001
  run_in "$REPO" --bg my-topic "a later prompt"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt")" = "a launch in the same second" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120001.txt")" = "a later prompt" ]
  [ "$(wc -l < "$SLEEP_LOG" | tr -d ' ')" -eq 1 ]
}

@test "a clock that stays on a taken second → L003 after three reads, nothing written" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'a launch in the same second\n' > "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt"
  before="$(_prompt_files "$REPO/my-topic")"
  clock_stub 20260930-120000
  run_in "$REPO" --bg my-topic "a later prompt"
  [ "$status" -eq 1 ]
  _contains "$output" "L003"
  _contains "$output" "no free name"
  [ "$(wc -l < "$DATE_LOG" | tr -d ' ')" -eq 3 ]
  [ "$(wc -l < "$SLEEP_LOG" | tr -d ' ')" -eq 2 ]
  [ "$(_prompt_files "$REPO/my-topic")" = "$before" ]
  [ ! -e "$ARGS_FILE" ]
}

@test "a repeat of the first prompt writes nothing and says so" {
  mkdir -p "$REPO/my-topic"
  printf 'the same prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  run_in "$REPO" --bg my-topic "the same prompt"
  [ "$status" -eq 0 ]
  first="$REPO/my-topic/prompt-new-agent-launch.txt"
  _contains "$output" "Repeat: the prompt matches $first, so no new file was written."
  _contains "$output" "Prompt: $first"
  [ "$(_prompt_files "$REPO/my-topic")" = "prompt-new-agent-launch.txt" ]
}

@test "a repeat of the newest update file writes nothing and names that file" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'the second prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-100000.txt"
  before="$(_prompt_files "$REPO/my-topic")"
  run_in "$REPO" --bg my-topic "the second prompt"
  [ "$status" -eq 0 ]
  _contains "$output" "Prompt: $REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-100000.txt"
  _contains "$output" "Repeat:"
  [ "$(_prompt_files "$REPO/my-topic")" = "$before" ]
}

@test "a repeat of the newest old-form update file writes nothing" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'the second prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.update-20260930-100000.txt"
  before="$(_prompt_files "$REPO/my-topic")"
  run_in "$REPO" --bg my-topic "the second prompt"
  [ "$status" -eq 0 ]
  _contains "$output" "Repeat: the prompt matches $REPO/my-topic/prompt-new-agent-launch.update-20260930-100000.txt"
  [ "$(_prompt_files "$REPO/my-topic")" = "$before" ]
}

@test "with both forms, the repeat check compares the highest stamp, not the last file of the glob" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'the older prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260929-090000.txt"
  printf 'the newest prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.update-20260930-100000.txt"
  before="$(_prompt_files "$REPO/my-topic")"
  run_in "$REPO" --bg my-topic "the newest prompt"
  [ "$status" -eq 0 ]
  _contains "$output" "Repeat: the prompt matches $REPO/my-topic/prompt-new-agent-launch.update-20260930-100000.txt"
  [ "$(_prompt_files "$REPO/my-topic")" = "$before" ]
}

@test "with both forms, a repeat of the newest new-form file writes nothing" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'the older prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.update-20260929-090000.txt"
  printf 'the newest prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-100000.txt"
  before="$(_prompt_files "$REPO/my-topic")"
  run_in "$REPO" --bg my-topic "the newest prompt"
  [ "$status" -eq 0 ]
  _contains "$output" "Repeat: the prompt matches $REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-100000.txt"
  [ "$(_prompt_files "$REPO/my-topic")" = "$before" ]
}

@test "with both forms, a prompt that matches the older file is a new update file" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'the older prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260929-090000.txt"
  printf 'the newest prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.update-20260930-100000.txt"
  clock_stub 20260930-120000
  run_in "$REPO" --bg my-topic "the older prompt"
  [ "$status" -eq 0 ]
  _lacks "$output" "Repeat:"
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt")" = "the older prompt" ]
}

@test "a stamp that an old-form file holds is taken, so the launch waits for the next second" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'an old-form launch\n' > "$REPO/my-topic/prompt-new-agent-launch.update-20260930-120000.txt"
  clock_stub 20260930-120000 20260930-120001
  run_in "$REPO" --bg my-topic "a later prompt"
  [ "$status" -eq 0 ]
  [ ! -e "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120001.txt")" = "a later prompt" ]
  [ "$(wc -l < "$SLEEP_LOG" | tr -d ' ')" -eq 1 ]
}

@test "a hand-named update file with a dot before the stamp never counts as the newest prompt" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'a hand-named prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.update.20260930-100000.txt"
  clock_stub 20260930-120000
  run_in "$REPO" --bg my-topic "a hand-named prompt"
  [ "$status" -eq 0 ]
  _lacks "$output" "Repeat:"
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt")" = "a hand-named prompt" ]
}

@test "an update file whose suffix is not a stamp never counts as the newest prompt" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'a draft\n' > "$REPO/my-topic/prompt-new-agent-launch.txt.update-draft.txt"
  clock_stub 20260930-120000
  run_in "$REPO" --bg my-topic "a draft"
  [ "$status" -eq 0 ]
  _lacks "$output" "Repeat:"
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt")" = "a draft" ]
}

@test "a prompt that matches an older file but not the newest is a new update file" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'the second prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-100000.txt"
  clock_stub 20260930-120000
  run_in "$REPO" --bg my-topic "the first prompt"
  [ "$status" -eq 0 ]
  _lacks "$output" "Repeat:"
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt")" = "the first prompt" ]
}

@test "an old archive keeps its name and bytes, and is never taken as the newest prompt" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'an archived prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.20200102-153045.txt"
  clock_stub 20260930-120000
  run_in "$REPO" --bg my-topic "an archived prompt"
  [ "$status" -eq 0 ]
  _lacks "$output" "Repeat:"
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.20200102-153045.txt")" = "an archived prompt" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt")" = "an archived prompt" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "the first prompt" ]
}

@test "--bg on a later launch names the update file in the preamble" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  clock_stub 20260930-120000
  run_in "$REPO" --bg my-topic "a later prompt"
  [ "$status" -eq 0 ]
  _contains "$(cat "$ARGS_FILE")" "already saved at $REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt"
}

@test "--bg on a repeat names the matched file in the preamble" {
  mkdir -p "$REPO/my-topic"
  printf 'the same prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  run_in "$REPO" --bg my-topic "the same prompt"
  [ "$status" -eq 0 ]
  _contains "$(cat "$ARGS_FILE")" "already saved at $REPO/my-topic/prompt-new-agent-launch.txt,"
}

@test "a session file of another session for the folder → a hint to /resume-agent, and the launch goes on" {
  mkdir -p "$REPO/my-topic" "$SESSIONS_DIR"
  printf '{"version":1,"folder":"%s","session_id":"7fa0c639-1111-4222-8333-944455556666","slug":"t","written_at":"2026-10-13T10:00:00Z"}' \
    "$REPO/my-topic" > "$SESSIONS_DIR/7fa0c639-1111-4222-8333-944455556666--t.json"
  run_in "$REPO" --bg my-topic "a later prompt"
  [ "$status" -eq 0 ]
  _contains "$output" "launch-agent: session 7fa0c639 used this folder before; to continue that session rather than start with no context, use /resume-agent $REPO/my-topic"
  [ -e "$ARGS_FILE" ]
}

@test "the session file of the calling session gives no hint" {
  mkdir -p "$REPO/my-topic" "$SESSIONS_DIR"
  printf '{"version":1,"folder":"%s","session_id":"%s","slug":"t","written_at":"2026-10-13T10:00:00Z"}' \
    "$REPO/my-topic" "$SESSION_ID" > "$SESSIONS_DIR/$SESSION_ID--t.json"
  run_here "$REPO" my-topic "a later prompt"
  [ "$status" -eq 0 ]
  [[ "$output" != *"/resume-agent"* ]] || false
}

@test "a session file for another folder gives no hint" {
  mkdir -p "$REPO/my-topic" "$REPO/elsewhere" "$SESSIONS_DIR"
  printf '{"version":1,"folder":"%s","session_id":"7fa0c639-1111-4222-8333-944455556666","slug":"t","written_at":"2026-10-13T10:00:00Z"}' \
    "$REPO/elsewhere" > "$SESSIONS_DIR/7fa0c639-1111-4222-8333-944455556666--t.json"
  run_in "$REPO" --bg my-topic "a prompt"
  [ "$status" -eq 0 ]
  [[ "$output" != *"/resume-agent"* ]] || false
}

@test "the default mode on a later launch adopts the folder and reports the update file" {
  mkdir -p "$REPO/my-topic"
  printf 'the first prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  clock_stub 20260930-120000
  run_here "$REPO" my-topic "a later prompt"
  [ "$status" -eq 0 ]
  _contains "$output" "Prompt: $REPO/my-topic/prompt-new-agent-launch.txt.update-20260930-120000.txt"
  _contains "$output" "Here: no agent was started"
  [ "$(wc -l < "$DATE_LOG" | tr -d ' ')" -eq 1 ]
}

@test "the first prompt lists first and the update files follow in stamp order (C locale)" {
  dir="$TEST_TEMP_DIR/order"
  mkdir -p "$dir"
  touch "$dir/prompt-new-agent-launch.txt.update-20260930-120000.txt" \
    "$dir/prompt-new-agent-launch.txt" \
    "$dir/prompt-new-agent-launch.txt.update-20260929-090000.txt"
  expected="prompt-new-agent-launch.txt
prompt-new-agent-launch.txt.update-20260929-090000.txt
prompt-new-agent-launch.txt.update-20260930-120000.txt"
  [ "$(cd "$dir" && LC_ALL=C ls -1)" = "$expected" ]
}

@test "the first prompt lists first and the update files follow in stamp order (en_US.UTF-8)" {
  locale_name="$(locale -a 2>/dev/null | grep -i -m 1 '^en_US\.utf-\{0,1\}8$' || true)"
  [ -n "$locale_name" ] || skip "en_US.UTF-8 is not installed"
  dir="$TEST_TEMP_DIR/order"
  mkdir -p "$dir"
  touch "$dir/prompt-new-agent-launch.txt.update-20260930-120000.txt" \
    "$dir/prompt-new-agent-launch.txt" \
    "$dir/prompt-new-agent-launch.txt.update-20260929-090000.txt"
  expected="prompt-new-agent-launch.txt
prompt-new-agent-launch.txt.update-20260929-090000.txt
prompt-new-agent-launch.txt.update-20260930-120000.txt"
  [ "$(cd "$dir" && LC_ALL="$locale_name" ls -1)" = "$expected" ]
}

# ============================================================================
# The display name
# ============================================================================

@test "display name defaults to the folder basename and reaches claude" {
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: my-topic"* ]] || false
  [[ "$(cat "$ARGS_FILE")" == *"--name my-topic"* ]] || false
}

# ============================================================================
# The child's working directory and prompt
# ============================================================================

@test "child starts in the repository root that contains the folder" {
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "$(cat "$CWD_FILE")" = "$(cd "$REPO" && pwd -P)" ]
}

@test "child starts in the folder itself when it is in no repository" {
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_in "$REPO" --bg "$target" "do the thing"
  [ "$status" -eq 0 ]
  [ "$(cat "$CWD_FILE")" = "$(cd "$target" && pwd -P)" ]
}

@test "preamble names the folder, the set-work-folder call, and the saved prompt" {
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  args="$(cat "$ARGS_FILE")"
  [[ "$args" == *"Your work folder is $REPO/my-topic."* ]] || false
  _contains "$args" "set-work-folder.sh '$REPO/my-topic' 'my-topic'"
  [[ "$args" == *"already saved at $REPO/my-topic/prompt-new-agent-launch.txt"* ]] || false
  [[ "$args" == *"do the thing"* ]] || false
}

@test "CLAUDE.md sentence appears when the child's working directory has one" {
  printf 'repo rules\n' > "$REPO/CLAUDE.md"
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$(cat "$ARGS_FILE")" == *"Then read $REPO/CLAUDE.md and follow it."* ]] || false
}

@test "CLAUDE.md sentence is absent when there is no such file" {
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$(cat "$ARGS_FILE")" != *"and follow it"* ]] || false
}

# ============================================================================
# Dispatch
# ============================================================================

# Whole-line assertions, because the defect these guard against joined the
# status line and the hint lines into one token that still contained the id.
@test "success reports the bare job id and the attach command" {
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "${lines[$((${#lines[@]} - 2))]}" = "Job: a1b2c3d4" ]
  [ "${lines[$((${#lines[@]} - 1))]}" = "Attach: claude attach a1b2c3d4" ]
}

@test "ANSI color codes around the status line do not reach the job id" {
  run env PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" \
    STUB_OUTPUT='\033[1mbackgrounded\033[0m · \033[36ma1b2c3d4\033[39m · \033]8;;https://example.invalid\007my-topic\033]8;;\007\n  claude agents             list sessions' \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "${lines[$((${#lines[@]} - 2))]}" = "Job: a1b2c3d4" ]
  [ "${lines[$((${#lines[@]} - 1))]}" = "Attach: claude attach a1b2c3d4" ]
}

@test "the resolved folder is the first line of output" {
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Folder: $REPO/my-topic" ]
}

@test "dispatch failure → exit 1, folder and prompt kept, pasteable command printed" {
  run env PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" STUB_FAIL=1 \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" --bg my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L004"* ]] || false
  [[ "$output" == *"claude --bg --name 'my-topic'"* ]] || false
  [ -d "$REPO/my-topic" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "do the thing" ]
}

# The apostrophe tests assert the escaped text rather than running the printed
# command. Evaluating it would prove pasteability, but on the failing side of the
# test the quoting is broken by definition, so the eval would run whatever the
# break exposes. The escaped form is the contract, so the escaped form is what
# these assert.
@test "dispatch failure escapes an apostrophe in the name and in the prompt" {
  topic="$TEST_TEMP_DIR/Charles' agent"
  run env PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" STUB_FAIL=1 \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" --bg "$topic" \
    "Fix the user's bug"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L004"* ]] || false
  _contains "$output" "--name 'Charles'\\'' agent'"
  _contains "$output" "Fix the user'\\''s bug'"
  # The child prompt the stub recorded is the unescaped original, so the quoted
  # set-work-folder call reads there the way the child will run it.
  _contains "$(cat "$ARGS_FILE")" "set-work-folder.sh '$TEST_TEMP_DIR/Charles'\\'' agent' 'Charles'\\'' agent'"
}

# The agent already runs when these fail, so the message must name it, point at
# `claude agents`, and never offer the relaunch command the dispatch failure
# above prints: that command would start a second agent.
@test "a launch that prints nothing → L004 that says the agent runs, with no relaunch" {
  run env PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" STUB_SILENT=1 \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" --bg my-topic "do the thing"
  [ "$status" -eq 1 ]
  _contains "$output" "L004"
  _contains "$output" "the agent started as my-topic"
  _contains "$output" "claude agents"
  _contains "$output" "do not launch it again"
  _contains "$output" "claude --bg printed nothing"
  _lacks "$output" "claude --bg --name"
  _lacks "$output" "Job:"
  _lacks "$output" "Attach:"
}

@test "a status line with no separator → L004 with the cleaned output, and no relaunch" {
  run env PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" \
    STUB_OUTPUT='\033[1mbackgrounded a1b2c3d4\033[0m\n  claude agents             list sessions' \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" --bg my-topic "do the thing"
  [ "$status" -eq 1 ]
  _contains "$output" "L004"
  _contains "$output" "the agent started as my-topic"
  _contains "$output" "claude agents"
  _contains "$output" "do not launch it again"
  _contains "$output" "  backgrounded a1b2c3d4"
  _lacks "$output" $'\033'
  _lacks "$output" "claude --bg --name"
  _lacks "$output" "Job:"
  _lacks "$output" "Attach:"
}

@test "claude missing from PATH is a dispatch failure, and the prompt survives it" {
  bare="$TEST_TEMP_DIR/bare"
  _stub_path_without "$bare" claude >/dev/null
  run env PATH="$bare" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" --bg my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L004"* ]] || false
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "do the thing" ]
}

# ============================================================================
# The default mode: this session adopts the folder
# ============================================================================

@test "the default mode starts no agent and says so" {
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Here: no agent was started"* ]] || false
  [[ "$output" != *"Job:"* ]] || false
  [[ "$output" != *"Attach:"* ]] || false
  [ ! -f "$ARGS_FILE" ]
}

@test "the default mode creates the folder and saves the prompt, as --bg does" {
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Folder: $REPO/my-topic" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "do the thing" ]
}

@test "the default mode points this session's working files at the folder" {
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ -f "$SESSIONS_DIR/${SESSION_ID}--my-topic.json" ]
}

@test "the resolver then answers with the folder for this session" {
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  run env -u CLAUDE_JOB_DIR -u CLAUDE_CODE_AGENT -u CLAUDE_PID \
    -u CLAUDE_CODE_CHILD_SESSION \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    bash -c 'cd "$1" && shift && exec "$@"' _ "$REPO" "$RESOLVER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$REPO/my-topic"* ]] || false
}

@test "the default mode ends with the /rename line for the folder name" {
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "Type /rename my-topic to give this session the folder name." ]
}

@test "the default mode takes a folder outside the launcher's repository" {
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_here "$REPO" "$target" "do the thing"
  [ "$status" -eq 0 ]
  [ "$(cat "$target/prompt-new-agent-launch.txt")" = "do the thing" ]
  [ -f "$SESSIONS_DIR/${SESSION_ID}--topic.json" ]
}

@test "the default mode outside a session → L005 pointing at --bg, nothing created" {
  run env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_JOB_DIR -u CLAUDE_CODE_AGENT \
    -u CLAUDE_PID -u CLAUDE_CODE_CHILD_SESSION \
    PATH="$STUB_PATH" MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L005"* ]] || false
  [[ "$output" == *"CLAUDE_CODE_SESSION_ID"* ]] || false
  [[ "$output" == *"pass --bg"* ]] || false
  [ ! -d "$REPO/my-topic" ]
}

@test "the default mode refuses a near-match slug too, and creates nothing" {
  mkdir -p "$REPO/my_topic"
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]] || false
  [ ! -d "$REPO/my-topic" ]
}

@test "a folder that cannot be adopted → L005, folder and prompt kept, pasteable command printed" {
  bare="$TEST_TEMP_DIR/nojq"
  _stub_path_without "$bare" jq > /dev/null
  # An absolute folder, because without jq the settings file cannot be read,
  # and a slug then refuses with L002 before adoption is tried.
  run env -u CLAUDE_JOB_DIR -u CLAUDE_CODE_AGENT -u CLAUDE_PID \
    -u CLAUDE_CODE_CHILD_SESSION \
    PATH="$bare" MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" "$REPO/my-topic" "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L005"* ]] || false
  [[ "$output" == *"set-work-folder.sh' '$REPO/my-topic' 'my-topic'"* ]] || false
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "do the thing" ]
}

@test "a folder that cannot be adopted with --take-over → L005, the printed command carries --take-over" {
  bare="$TEST_TEMP_DIR/nojq-take-over"
  _stub_path_without "$bare" jq > /dev/null
  run env -u CLAUDE_JOB_DIR -u CLAUDE_CODE_AGENT -u CLAUDE_PID \
    -u CLAUDE_CODE_CHILD_SESSION \
    PATH="$bare" MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" --take-over "$REPO/my-topic" "do the thing"
  [ "$status" -eq 1 ]
  _contains "$output" "L005"
  _contains "$output" "set-work-folder.sh' --take-over '$REPO/my-topic' 'my-topic'"
}

@test "adoption failure escapes apostrophes in the folder and in the name" {
  topic="$TEST_TEMP_DIR/Charles' topics/Ann's run"
  bare="$TEST_TEMP_DIR/nojq-apostrophe"
  _stub_path_without "$bare" jq > /dev/null
  run env -u CLAUDE_JOB_DIR -u CLAUDE_CODE_AGENT -u CLAUDE_PID \
    -u CLAUDE_CODE_CHILD_SESSION \
    PATH="$bare" MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" "$topic" "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L005"* ]] || false
  # The script's own path is quoted too, so the apostrophe after .sh is the
  # closing quote of the first word rather than part of the name.
  _contains "$output" "set-work-folder.sh' '$TEST_TEMP_DIR/Charles'\\'' topics/Ann'\\''s run' 'Ann'\\''s run'"
  [ "$(cat "$topic/prompt-new-agent-launch.txt")" = "do the thing" ]
}

# ============================================================================
# The depth limit
# ============================================================================

DEPTH_DIR_NAME="agent-depth"

# run_bg_as <session-id> <args...> — run the script from $REPO with --bg as the
# session <session-id>, so the depth check reads that session's record.
run_bg_as() {
  local sid="$1"
  shift
  run env -u CLAUDE_JOB_DIR -u CLAUDE_CODE_AGENT -u CLAUDE_PID \
    -u CLAUDE_CODE_CHILD_SESSION \
    PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$sid" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" "$@"
}

# depth_record <job-id> <depth> — write a depth record, as a parent would.
depth_record() {
  mkdir -p "$TEST_TEMP_DIR/$DEPTH_DIR_NAME"
  printf '%s\n' "$2" > "$TEST_TEMP_DIR/$DEPTH_DIR_NAME/$1"
}

@test "depth: a launch from a session with no record writes depth 1 for the child's job id" {
  run_bg_as "$SESSION_ID" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  # The stub prints job id a1b2c3d4.
  [ "$(cat "$TEST_TEMP_DIR/$DEPTH_DIR_NAME/a1b2c3d4")" = "1" ]
}

@test "depth: a launch from a plain shell is depth 0, so the child is depth 1" {
  run_in "$REPO" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/$DEPTH_DIR_NAME/a1b2c3d4")" = "1" ]
}

@test "depth: a session at depth 1 starts a child at depth 2" {
  depth_record "${SESSION_ID:0:8}" 1
  run_bg_as "$SESSION_ID" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/$DEPTH_DIR_NAME/a1b2c3d4")" = "2" ]
}

@test "depth: a session at the default limit → L006 naming the limit and the setting, nothing created" {
  depth_record "${SESSION_ID:0:8}" 2
  run_bg_as "$SESSION_ID" --bg my-topic "do the thing"
  [ "$status" -eq 1 ]
  _contains "$output" "L006"
  _contains "$output" "depth 2"
  _contains "$output" "launchAgentMaxDepth is 2"
  [ ! -e "$REPO/my-topic" ]
  [ ! -e "$ARGS_FILE" ]
}

@test "depth: launchAgentMaxDepth raises the limit" {
  printf '%s' '{"launchAgentMaxDepth": 3}' > "$CFG"
  depth_record "${SESSION_ID:0:8}" 2
  run_bg_as "$SESSION_ID" --bg my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/$DEPTH_DIR_NAME/a1b2c3d4")" = "3" ]
}

@test "depth: launchAgentMaxDepth 0 refuses every background launch" {
  printf '%s' '{"launchAgentMaxDepth": 0}' > "$CFG"
  run_bg_as "$SESSION_ID" --bg my-topic "do the thing"
  [ "$status" -eq 1 ]
  _contains "$output" "L006"
  _contains "$output" "launchAgentMaxDepth is 0"
}

@test "depth: a damaged record refuses rather than reading as 0" {
  depth_record "${SESSION_ID:0:8}" "two"
  run_bg_as "$SESSION_ID" --bg my-topic "do the thing"
  [ "$status" -eq 1 ]
  _contains "$output" "L006"
  _contains "$output" "cannot be read"
  [ ! -e "$REPO/my-topic" ]
}

@test "depth: the default mode neither reads nor writes a record" {
  depth_record "${SESSION_ID:0:8}" 9
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [ "$(ls "$TEST_TEMP_DIR/$DEPTH_DIR_NAME")" = "${SESSION_ID:0:8}" ]
}

@test "depth: a record that cannot be written → L006 naming claude stop, and no relaunch" {
  _require_enforced_permission_bits
  mkdir -p "$TEST_TEMP_DIR/$DEPTH_DIR_NAME"
  chmod 500 "$TEST_TEMP_DIR/$DEPTH_DIR_NAME"
  run_bg_as "$SESSION_ID" --bg my-topic "do the thing"
  chmod 700 "$TEST_TEMP_DIR/$DEPTH_DIR_NAME"
  [ "$status" -eq 1 ]
  _contains "$output" "L006"
  _contains "$output" "claude stop a1b2c3d4"
  _lacks "$output" "claude --bg --name"
}

# ============================================================================
# One session for each folder (issue 295, part 2)
# ============================================================================

HOLDER_ID="7fa0c639-1111-4222-8333-944455556666"

# holder <status|null> <pid|null> — a session file of HOLDER_ID for
# $REPO/my-topic, and its row in the list.
holder() {
  mkdir -p "$REPO/my-topic" "$SESSIONS_DIR"
  printf '{"version":1,"folder":"%s","session_id":"%s","written_at":"2026-10-13T10:00:00Z"}' \
    "$REPO/my-topic" "$HOLDER_ID" > "$SESSIONS_DIR/$HOLDER_ID--t.json"
  local status="\"$1\""
  [ "$1" != "null" ] || status="null"
  printf '[{"id":"%s","sessionId":"%s","name":"my-topic","status":%s,"pid":%s,"kind":"background","state":"blocked"}]' \
    "${HOLDER_ID:0:8}" "$HOLDER_ID" "$status" "$2" > "$AGENTS_FILE"
}

@test "held: a running session holds the folder → L007 with the /resume-agent command, and nothing is written" {
  holder idle 123
  run_here "$REPO" my-topic "a prompt"
  [ "$status" -eq 1 ]
  _contains "$output" "L007"
  _contains "$output" "session $HOLDER_ID (running, job ${HOLDER_ID:0:8}, name 'my-topic') holds $REPO/my-topic"
  _contains "$output" "use /resume-agent $REPO/my-topic"
  _contains "$output" "launch again with --take-over"
  [ ! -e "$REPO/my-topic/prompt-new-agent-launch.txt" ]
  [ ! -e "$SESSIONS_DIR/$SESSION_ID--my-topic.json" ]
}

@test "held: a retired session holds the folder → L007 for --bg, and no agent starts" {
  holder null null
  run_in "$REPO" --bg my-topic "a prompt"
  [ "$status" -eq 1 ]
  _contains "$output" "(retired"
  [ ! -e "$ARGS_FILE" ]
}

@test "held: --take-over in the default mode passes the take-over to set-work-folder.sh" {
  holder idle 123
  run_here "$REPO" --take-over my-topic "a prompt"
  [ "$status" -eq 0 ]
  [ ! -e "$SESSIONS_DIR/$HOLDER_ID--t.json" ]
  [ -f "$SESSIONS_DIR/$SESSION_ID--my-topic.json" ]
  _contains "$output" "set-work-folder: took $REPO/my-topic from session $HOLDER_ID"
  _contains "$output" "claude stop ${HOLDER_ID:0:8}"
}

@test "held: --bg --take-over passes the take-over to the child and keeps the file of the other session" {
  holder idle 123
  run_in "$REPO" --bg --take-over my-topic "a prompt"
  [ "$status" -eq 0 ]
  [ -f "$SESSIONS_DIR/$HOLDER_ID--t.json" ]
  _contains "$(cat "$ARGS_FILE")" "set-work-folder.sh --take-over '$REPO/my-topic' 'my-topic'"
  _contains "$output" "launch-agent: takeover dispatched for $REPO/my-topic from session $HOLDER_ID"
  _contains "$output" "stop it with claude stop ${HOLDER_ID:0:8}"
}

@test "held: --bg --take-over with a failed dispatch → L004, and the other session keeps the folder" {
  holder idle 123
  run env -u CLAUDE_CODE_SESSION_ID \
    PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" STUB_FAIL=1 \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" --bg --take-over my-topic "a prompt"
  [ "$status" -eq 1 ]
  _contains "$output" "L004"
  [ -f "$SESSIONS_DIR/$HOLDER_ID--t.json" ]
  _lacks "$output" "takeover dispatched"
}

@test "held: without --take-over, the child prompt runs set-work-folder.sh with no take-over" {
  run_in "$REPO" --bg my-topic "a prompt"
  [ "$status" -eq 0 ]
  _contains "$(cat "$ARGS_FILE")" "set-work-folder.sh '$REPO/my-topic' 'my-topic'"
  _lacks "$(cat "$ARGS_FILE")" "--take-over"
}

@test "held: --bg from the session that holds the folder → L007, also with --take-over" {
  mkdir -p "$REPO/my-topic" "$SESSIONS_DIR"
  printf '{"version":1,"folder":"%s","session_id":"%s","written_at":"2026-10-13T10:00:00Z"}' \
    "$REPO/my-topic" "$SESSION_ID" > "$SESSIONS_DIR/$SESSION_ID--t.json"
  printf '[{"id":"%s","sessionId":"%s","name":"me","status":"busy","pid":1,"kind":"interactive","state":null}]' \
    "${SESSION_ID:0:8}" "$SESSION_ID" > "$AGENTS_FILE"
  run_here "$REPO" --bg --take-over my-topic "a prompt"
  [ "$status" -eq 1 ]
  _contains "$output" "L007"
  _contains "$output" "this session holds $REPO/my-topic"
  _contains "$output" "launch the agent into another folder, or do the work in this session"
  [ ! -e "$ARGS_FILE" ]
  [ -f "$SESSIONS_DIR/$SESSION_ID--t.json" ]
}

@test "held: the default mode in the folder this session already holds is not refused" {
  mkdir -p "$REPO/my-topic" "$SESSIONS_DIR"
  printf '{"version":1,"folder":"%s","session_id":"%s","written_at":"2026-10-13T10:00:00Z"}' \
    "$REPO/my-topic" "$SESSION_ID" > "$SESSIONS_DIR/$SESSION_ID--t.json"
  run_here "$REPO" my-topic "a prompt"
  [ "$status" -eq 0 ]
}

@test "held: a check that cannot run lets the launch go on, with one stderr line" {
  holder idle 123
  run env -u CLAUDE_CODE_SESSION_ID PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" STUB_AGENTS_FAIL=1 \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" --bg my-topic "a prompt"
  [ "$status" -eq 0 ]
  [ -e "$ARGS_FILE" ]
  _contains "$output" "launch-agent: could not check whether another session holds $REPO/my-topic (claude agents --json failed"
  [ "$(printf '%s\n' "$output" | grep -c 'could not check')" -eq 1 ]
}

@test "held: a folder that does not exist yet is not checked" {
  run_in "$REPO" --bg new-topic "a prompt"
  [ "$status" -eq 0 ]
  [[ "$output" != *"could not check"* ]] || false
}
