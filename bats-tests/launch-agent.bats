#!/usr/bin/env bats
#
# Tests for skills/launch-agent/launch-agent.sh — folder resolution, the
# near-match slug guard, prompt resolution and rotation, preamble composition,
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
  run_in "$REPO" --bg thing "do it"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]]
  [[ "$output" == *"the folder comes first"* ]]
}

@test "--name → L001 saying it was removed, nothing created" {
  run_here "$REPO" my-topic --name thing "do it"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]]
  [[ "$output" == *"--name was removed"* ]]
  [ ! -d "$REPO/my-topic" ]
}

@test "--here → L001 saying it was removed, nothing created" {
  run_here "$REPO" my-topic --here "do it"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L001"* ]]
  [[ "$output" == *"--here was removed"* ]]
  [ ! -d "$REPO/my-topic" ]
}

@test "folder, no prompt argument, and empty stdin → L001" {
  : > "$TEST_TEMP_DIR/empty.txt"
  run_here_stdin "$REPO" "$TEST_TEMP_DIR/empty.txt" my-topic
  [ "$status" -eq 1 ]
  [[ "$output" == *"a task prompt is required"* ]]
  [ ! -d "$REPO/my-topic" ]
}

# ============================================================================
# Folder resolution
# ============================================================================

@test "slug resolves to <repo-root>/<slug>, not into .claude-work" {
  run_in "$REPO" my-topic --bg "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Folder: $REPO/my-topic"* ]]
  [ -d "$REPO/my-topic" ]
  [ ! -d "$REPO/.claude-work/my-topic" ]
}

@test "slug resolves against the main checkout when run from a subdirectory" {
  mkdir -p "$REPO/src/deep"
  run_in "$REPO/src/deep" my-topic --bg "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Folder: $REPO/my-topic"* ]]
}

@test "absolute path is used as given, outside any repository" {
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_in "$REPO" "$target" --bg "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Folder: $target"* ]]
  [ -d "$target" ]
}

@test "absolute path with a trailing slash still names the job after the basename" {
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_in "$REPO" "$target/" --bg "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: topic"* ]]
}

@test "existing folder is reused, not refused" {
  mkdir -p "$REPO/my-topic"
  run_in "$REPO" my-topic --bg "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Folder: $REPO/my-topic"* ]]
}

@test "folder path that exists as a regular file → L002, nothing written" {
  : > "$TEST_TEMP_DIR/afile"
  run_in "$REPO" "$TEST_TEMP_DIR/afile" --bg "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"is not a directory"* ]]
  [ ! -f "$ARGS_FILE" ]
}

@test "slug outside a git repository → L002 asking for an absolute path" {
  outside="$TEST_TEMP_DIR/no-repo"
  mkdir -p "$outside"
  run_in "$outside" my-topic --bg "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"pass an absolute path instead"* ]]
  [ ! -d "$outside/my-topic" ]
}

@test "slug containing a separator → L002, nothing created" {
  run_in "$REPO" team/onboarding --bg "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"is not a single path component"* ]]
  [ ! -d "$REPO/team" ]
}

@test "slug of .. → L002, nothing created outside the root" {
  run_in "$REPO" .. --bg "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"is not a topic name"* ]]
}

@test "slug naming a symlink to a directory resolves to the link's target" {
  outside="$TEST_TEMP_DIR/outside"
  mkdir -p "$outside"
  ln -s "$outside" "$REPO/linked"
  run_in "$REPO" linked --bg "do the thing"
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
  run_in "$REPO" my-topic --bg "do the thing"
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
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"launchAgentDefaultFolder"* ]]
  [[ "$output" == *"'$TEST_TEMP_DIR/not-there'"* ]]
  [[ "$output" == *"not an existing directory"* ]]
  [ ! -d "$TEST_TEMP_DIR/not-there" ]
  [ ! -d "$REPO/my-topic" ]
}

@test "the setting holding a relative path → L002, nothing written" {
  set_default_folder "topics"
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"'topics', which is not an absolute path"* ]]
  [ ! -d "$REPO/topics" ]
  [ ! -d "$REPO/my-topic" ]
}

@test "the setting is not expanded: a leading ~ is a relative path" {
  set_default_folder "~/topics"
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'~/topics', which is not an absolute path"* ]]
}

@test "the near-match guard runs against the setting's directory" {
  topics="$TEST_TEMP_DIR/topics"
  mkdir -p "$topics/my_topic"
  set_default_folder "$topics"
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nearly matches the existing 'my_topic' in $topics"* ]]
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
  run_in "$REPO" my-topic --bg "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"$CFG could not be read"* ]]
  [ ! -d "$REPO/my-topic" ]
  [ ! -f "$ARGS_FILE" ]
}

@test "an unreadable settings file → L002 for a slug, nothing written in the repository" {
  _require_enforced_permission_bits
  set_default_folder "$TEST_TEMP_DIR/topics"
  chmod 000 "$CFG"
  run_in "$REPO" my-topic --bg "do the thing"
  chmod 644 "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"could not be read"* ]]
  [ ! -d "$REPO/my-topic" ]
}

@test "a malformed settings file does not block an absolute folder" {
  printf '%s' '{"launchAgentDefaultFolder":' > "$CFG"
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_in "$REPO" "$target" --bg "do the thing"
  [ "$status" -eq 0 ]
  # The loader's warning comes first in the merged output, so match the line
  # anywhere rather than at lines[0].
  [[ "$output" == *"Folder: $target"* ]]
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
  run_in "$REPO" agent-launch-skill --bg "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
  [[ "$output" == *"nearly matches the existing 'agent_launch_skill'"* ]]
  [ ! -d "$REPO/agent-launch-skill" ]
}

@test "case-only difference is a near match too" {
  mkdir -p "$REPO/MyTopic"
  run_in "$REPO" mytopic --bg "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nearly matches the existing 'MyTopic'"* ]]
}

@test "exact match is not a refusal: a second agent joins an existing topic" {
  mkdir -p "$REPO/my-topic"
  run_in "$REPO" my-topic --bg "do the thing"
  [ "$status" -eq 0 ]
}

@test "a regular file that normalizes onto the slug does not refuse it" {
  : > "$REPO/my_topic"
  run_in "$REPO" my-topic --bg "do the thing"
  [ "$status" -eq 0 ]
  [ -d "$REPO/my-topic" ]
}

@test "an absolute path skips the guard, which is the way past a refusal" {
  mkdir -p "$REPO/agent_launch_skill"
  run_in "$REPO" "$REPO/agent-launch-skill" --bg "do the thing"
  [ "$status" -eq 0 ]
  [ -d "$REPO/agent-launch-skill" ]
}

# ============================================================================
# Prompt resolution
# ============================================================================

@test "multi-word prompt is written verbatim" {
  run_in "$REPO" my-topic --bg "do the thing" "and then another"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "do the thing and then another" ]
}

@test "single token naming a readable file contributes that file's content" {
  printf 'line one\nline two\n' > "$TEST_TEMP_DIR/prompt.txt"
  run_in "$REPO" my-topic --bg "$TEST_TEMP_DIR/prompt.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "$(printf 'line one\nline two')" ]
  [[ "$(cat "$ARGS_FILE")" == *"line two"* ]]
}

@test "path-shaped single token naming nothing → L003, nothing written" {
  run_in "$REPO" my-topic --bg ./plans/lanch-prompt.txt
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
  run_in "$REPO" my-topic --bg "$TEST_TEMP_DIR/prompt.md"
  chmod 644 "$TEST_TEMP_DIR/prompt.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L003"* ]]
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
    bash -c 'cd "$1" && shift && exec "$@" < "$0"' "$TEST_TEMP_DIR/stdin.txt" "$REPO" "$SCRIPT" my-topic --bg
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
  run_in "$REPO" my-topic --bg triage
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "triage" ]
}

@test "empty prompt → L003, nothing created" {
  run_in "$REPO" my-topic --bg ""
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
  run_in "$REPO" my-topic --bg "the newer prompt"
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
  run_in "$REPO" my-topic --bg "the newer prompt"
  [ "$status" -eq 0 ]
  [ -f "$REPO/my-topic/prompt-new-agent-launch.20200102-153045.txt" ]
}

@test "an archive name already taken gets a suffix rather than the earlier prompt" {
  mkdir -p "$REPO/my-topic"
  printf 'the earlier prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  touch -t 202001021530.45 "$REPO/my-topic/prompt-new-agent-launch.txt"
  printf 'an even earlier prompt\n' > "$REPO/my-topic/prompt-new-agent-launch.20200102-153045.txt"
  run_in "$REPO" my-topic --bg "the newer prompt"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.20200102-153045.txt")" = "an even earlier prompt" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.20200102-153045-001.txt")" = "the earlier prompt" ]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "the newer prompt" ]
}

@test "a modification time neither stat dialect reads → L003, earlier prompt kept" {
  mkdir -p "$REPO/my-topic"
  printf 'first\n' > "$REPO/my-topic/prompt-new-agent-launch.txt"
  bare="$TEST_TEMP_DIR/nostat"
  _stub_path_without "$bare" stat > /dev/null
  # _stub_path_without hides one tool, and this branch needs both gone: the BSD
  # arm calls stat alone, the GNU arm calls stat and then date.
  rm -f "$bare/date"
  run env PATH="$bare" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" my-topic --bg "second"
  [ "$status" -eq 1 ]
  _contains "$output" "L003"
  _contains "$output" "modification time"
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "first" ]
}

# ============================================================================
# The display name
# ============================================================================

@test "display name defaults to the folder basename and reaches claude" {
  run_in "$REPO" my-topic --bg "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name: my-topic"* ]]
  [[ "$(cat "$ARGS_FILE")" == *"--name my-topic"* ]]
}

# ============================================================================
# The child's working directory and prompt
# ============================================================================

@test "child starts in the repository root that contains the folder" {
  run_in "$REPO" my-topic --bg "do the thing"
  [ "$status" -eq 0 ]
  [ "$(cat "$CWD_FILE")" = "$(cd "$REPO" && pwd -P)" ]
}

@test "child starts in the folder itself when it is in no repository" {
  target="$TEST_TEMP_DIR/elsewhere/topic"
  run_in "$REPO" "$target" --bg "do the thing"
  [ "$status" -eq 0 ]
  [ "$(cat "$CWD_FILE")" = "$(cd "$target" && pwd -P)" ]
}

@test "preamble names the folder, the set-work-folder call, and the saved prompt" {
  run_in "$REPO" my-topic --bg "do the thing"
  [ "$status" -eq 0 ]
  args="$(cat "$ARGS_FILE")"
  [[ "$args" == *"Your work folder is $REPO/my-topic."* ]]
  _contains "$args" "set-work-folder.sh '$REPO/my-topic' 'my-topic'"
  [[ "$args" == *"already saved at $REPO/my-topic/prompt-new-agent-launch.txt"* ]]
  [[ "$args" == *"do the thing"* ]]
}

@test "CLAUDE.md sentence appears when the child's working directory has one" {
  printf 'repo rules\n' > "$REPO/CLAUDE.md"
  run_in "$REPO" my-topic --bg "do the thing"
  [ "$status" -eq 0 ]
  [[ "$(cat "$ARGS_FILE")" == *"Then read $REPO/CLAUDE.md and follow it."* ]]
}

@test "CLAUDE.md sentence is absent when there is no such file" {
  run_in "$REPO" my-topic --bg "do the thing"
  [ "$status" -eq 0 ]
  [[ "$(cat "$ARGS_FILE")" != *"and follow it"* ]]
}

# ============================================================================
# Dispatch
# ============================================================================

@test "success reports the job id and the attach command" {
  run_in "$REPO" my-topic --bg "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Job: bg_deadbeef"* ]]
  [[ "$output" == *"Attach: claude attach bg_deadbeef"* ]]
}

@test "the resolved folder is the first line of output" {
  run_in "$REPO" my-topic --bg "do the thing"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Folder: $REPO/my-topic" ]
}

@test "dispatch failure → exit 1, folder and prompt kept, pasteable command printed" {
  run env PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" STUB_FAIL=1 \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" my-topic --bg "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L004"* ]]
  [[ "$output" == *"claude --bg --name 'my-topic'"* ]]
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
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" "$topic" \
    --bg "Fix the user's bug"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L004"* ]]
  _contains "$output" "--name 'Charles'\\'' agent'"
  _contains "$output" "Fix the user'\\''s bug'"
  # The child prompt the stub recorded is the unescaped original, so the quoted
  # set-work-folder call reads there the way the child will run it.
  _contains "$(cat "$ARGS_FILE")" "set-work-folder.sh '$TEST_TEMP_DIR/Charles'\\'' agent' 'Charles'\\'' agent'"
}

@test "a launch that prints no id → L004 rather than an attach command for nothing" {
  run env PATH="$STUB_PATH" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" STUB_SILENT=1 \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" my-topic --bg "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L004"* ]]
  [[ "$output" == *"reported no job id"* ]]
}

@test "claude missing from PATH is a dispatch failure, and the prompt survives it" {
  bare="$TEST_TEMP_DIR/bare"
  _stub_path_without "$bare" claude >/dev/null
  run env PATH="$bare" ARGS_FILE="$ARGS_FILE" CWD_FILE="$CWD_FILE" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    bash -c 'cd "$1" && shift && exec "$@" < /dev/null' _ "$REPO" "$SCRIPT" my-topic --bg "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L004"* ]]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "do the thing" ]
}

# ============================================================================
# The default mode: this session adopts the folder
# ============================================================================

@test "the default mode starts no agent and says so" {
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Here: no agent was started"* ]]
  [[ "$output" != *"Job:"* ]]
  [[ "$output" != *"Attach:"* ]]
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
  [[ "$output" == *"$REPO/my-topic"* ]]
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
  [[ "$output" == *"L005"* ]]
  [[ "$output" == *"CLAUDE_CODE_SESSION_ID"* ]]
  [[ "$output" == *"pass --bg"* ]]
  [ ! -d "$REPO/my-topic" ]
}

@test "the default mode refuses a near-match slug too, and creates nothing" {
  mkdir -p "$REPO/my_topic"
  run_here "$REPO" my-topic "do the thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L002"* ]]
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
  [[ "$output" == *"L005"* ]]
  [[ "$output" == *"set-work-folder.sh' '$REPO/my-topic' 'my-topic'"* ]]
  [ "$(cat "$REPO/my-topic/prompt-new-agent-launch.txt")" = "do the thing" ]
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
  [[ "$output" == *"L005"* ]]
  # The script's own path is quoted too, so the apostrophe after .sh is the
  # closing quote of the first word rather than part of the name.
  _contains "$output" "set-work-folder.sh' '$TEST_TEMP_DIR/Charles'\\'' topics/Ann'\\''s run' 'Ann'\\''s run'"
  [ "$(cat "$topic/prompt-new-agent-launch.txt")" = "do the thing" ]
}
