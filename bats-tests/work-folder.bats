#!/usr/bin/env bats
#
# Tests for the worktree tier: marker-file.sh (the reader), work-folder.sh (the
# tier order), and work-folder-tier.sh (which tier won), exercised through
# get-issue-folder-path.sh where the behaviour is a resolved path.
#
# Every test points MY_CLAUDE_SKILLS_CONFIG at a temp settings file and works
# in a temp git repository, so a developer's real sessions directory and real
# checkouts can never change an outcome.

bats_require_minimum_version 1.7.0

load test_helper

RESOLVER="$PROJECT_ROOT/skills/issue-context/get-issue-folder-path.sh"
TIER="$PROJECT_ROOT/skills/issue-context/work-folder-tier.sh"
WRITER="$PROJECT_ROOT/skills/issue-context/set-work-folder.sh"
MARKER_NAME="CLAUDE_WORK_FOLDER"

SESSION_ID="06cb4128-c112-4696-bddb-3a52d1684a20"

# Every CLAUDE_* variable the scripts read is unset first: a bats run started
# from a Claude Code session inherits a real session id, and without this the
# worktree tier would be masked by the developer's own session override.
CLAUDE_ENV_RESET=(env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_JOB_DIR \
  -u CLAUDE_CODE_AGENT -u CLAUDE_PID -u CLAUDE_CODE_CHILD_SESSION)

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  cd "$TEST_TEMP_DIR"
  git init -q .
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  git checkout -q -B main
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{"segment":""}' > "$CFG"
  SESSIONS_DIR="$TEST_TEMP_DIR/sessions"
  TOPIC="$TEST_TEMP_DIR/topic"
  mkdir -p "$TOPIC"
  MARKER="$TEST_TEMP_DIR/$MARKER_NAME"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# Write the marker with the given contents, verbatim.
write_marker() {
  printf '%s' "$1" > "$MARKER"
}

resolve() {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$RESOLVER" "$@"
}

tier_of() {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$TIER" "$@"
}

# Give this session a valid override folder, so the session tier can outrank
# the worktree tier.
write_session_file() {
  mkdir -p "$SESSIONS_DIR"
  printf '{"version":1,"folder":"%s","session_id":"%s"}' \
    "$1" "$SESSION_ID" > "$SESSIONS_DIR/${SESSION_ID}.json"
}

# ============================================================================
# The marker resolves
# ============================================================================

@test "a marker holding an absolute path wins over the branch" {
  write_marker "$TOPIC"
  resolve
  [ "$status" -eq 0 ]
  [ "$output" = "$TOPIC" ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$stderr" == *"using $TOPIC"* ]]
}

@test "a trailing newline and surrounding spaces are trimmed" {
  printf '   %s  \n' "$TOPIC" > "$MARKER"
  resolve
  [ "$output" = "$TOPIC" ]
}

@test "only the first line is read" {
  printf '%s\nignored second line\n' "$TOPIC" > "$MARKER"
  resolve
  [ "$output" = "$TOPIC" ]
}

@test "a leading ~/ expands against HOME" {
  local home="$TEST_TEMP_DIR/home"
  mkdir -p "$home/topic"
  write_marker "~/topic"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" HOME="$home" "$RESOLVER"
  [ "$status" -eq 0 ]
  [ "$output" = "$home/topic" ]
}

@test "the folder is canonicalised, so a path through .. resolves once" {
  write_marker "$TOPIC/../topic"
  resolve
  [ "$output" = "$TOPIC" ]
  [[ "$output" != *".."* ]]
}

@test "a marker outside the repository is honoured" {
  local outside
  outside="$(mktemp -d)"
  outside="$(cd "$outside" && pwd -P)"
  write_marker "$outside"
  resolve
  [ "$output" = "$outside" ]
  rm -rf "$outside"
}

@test "the folder is not created by resolving it" {
  write_marker "$TEST_TEMP_DIR/not-there"
  resolve
  [ ! -e "$TEST_TEMP_DIR/not-there" ]
}

# ============================================================================
# The marker is refused, and says why
# ============================================================================

@test "no marker resolves the branch, silently" {
  resolve
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [[ "$stderr" != *"marker"* ]]
}

@test "an empty marker is ignored and reported" {
  write_marker ""
  resolve
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [[ "$stderr" == *"$MARKER_NAME is empty"* ]]
}

@test "a whitespace-only marker is ignored and reported" {
  printf '   \n' > "$MARKER"
  resolve
  [[ "$stderr" == *"$MARKER_NAME is empty"* ]]
}

@test "a relative path is ignored and reported" {
  write_marker "topic"
  resolve
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [[ "$stderr" == *"absolute path"* ]]
}

@test "a bare ~ without a slash is not expanded, so it is refused" {
  write_marker "~topic"
  resolve
  [[ "$stderr" == *"absolute path"* ]]
}

@test "a folder that does not exist is ignored and reported" {
  write_marker "$TEST_TEMP_DIR/not-there"
  resolve
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [[ "$stderr" == *"is not an existing directory"* ]]
}

@test "a path naming a file rather than a directory is ignored" {
  printf 'x' > "$TEST_TEMP_DIR/a-file"
  write_marker "$TEST_TEMP_DIR/a-file"
  resolve
  [[ "$stderr" == *"is not an existing directory"* ]]
}

@test "an unreadable marker is ignored and reported" {
  _require_enforced_permission_bits
  write_marker "$TOPIC"
  chmod a-r "$MARKER"
  resolve
  local err="$stderr"
  chmod u+r "$MARKER"
  [[ "$err" == *"could not be read"* ]]
}

@test "a marker naming a directory that cannot be entered is ignored, and nothing leaks to stderr" {
  # The -d test passes on a mode 000 directory whose parent is traversable, so
  # cd is what fails. Its own message must not escape: work-folder-tier.sh
  # promises an empty stderr, and every caller inherits this helper.
  _require_enforced_permission_bits
  local closed="$TEST_TEMP_DIR/closed"
  mkdir -p "$closed"
  write_marker "$closed"
  chmod 000 "$closed"
  resolve
  local err="$stderr"
  chmod 755 "$closed"
  [[ "$err" == *"could not be resolved"* ]]
  # The resolver prefixes every line it writes with its own name, so stderr
  # naming work-folder.sh at all means cd reported from underneath it.
  [[ "$err" != *"work-folder.sh"* ]]
}

@test "a marker in a sibling worktree's root is not read" {
  # The marker is per-worktree by construction: it is found at this
  # worktree's toplevel and nowhere else.
  local sibling="${TEST_TEMP_DIR}-sibling"
  mkdir -p "$sibling"
  printf '%s' "$TOPIC" > "$sibling/$MARKER_NAME"
  resolve
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  rm -rf "$sibling"
}

# ============================================================================
# Tier order
# ============================================================================

@test "the session override outranks the marker" {
  local sess="$TEST_TEMP_DIR/session-folder"
  mkdir -p "$sess"
  write_marker "$TOPIC"
  write_session_file "$sess"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" "$RESOLVER"
  [ "$output" = "$sess" ]
}

@test "a refused session override falls through to the marker, reporting both" {
  write_marker "$TOPIC"
  write_session_file "$TEST_TEMP_DIR/gone"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" "$RESOLVER"
  [ "$output" = "$TOPIC" ]
  [[ "$stderr" == *"override ignored"* ]]
  [[ "$stderr" == *"using $TOPIC"* ]]
}

@test "a refused marker falls through to the branch" {
  write_marker "$TEST_TEMP_DIR/gone"
  resolve
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
}

# ============================================================================
# --id honours the marker and bypasses the session override
# ============================================================================

@test "--id resolves under the marker, with no segment between" {
  write_marker "$TOPIC"
  resolve --id 42
  [ "$output" = "$TOPIC/42" ]
}

@test "--id under a marker ignores a configured segment" {
  printf '%s' '{"segment":"issues"}' > "$CFG"
  write_marker "$TOPIC"
  resolve --id 42
  [ "$output" = "$TOPIC/42" ]
}

@test "--id bypasses the session override and still honours the marker" {
  local sess="$TEST_TEMP_DIR/session-folder"
  mkdir -p "$sess"
  write_marker "$TOPIC"
  write_session_file "$sess"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" "$RESOLVER" --id 42
  [ "$output" = "$TOPIC/42" ]
  [[ "$stderr" == *"bypassed"* ]]
}

@test "--id with no marker is the branch-derived folder, unchanged" {
  resolve --id 42
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/42" ]
}

# ============================================================================
# work-folder-tier.sh
# ============================================================================

@test "tier: branch when nothing is set" {
  tier_of
  [ "$output" = "branch" ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "tier: worktree when only the marker is set" {
  write_marker "$TOPIC"
  tier_of
  [ "$output" = "worktree" ]
}

@test "tier: session when the override outranks a marker" {
  local sess="$TEST_TEMP_DIR/session-folder"
  mkdir -p "$sess"
  write_marker "$TOPIC"
  write_session_file "$sess"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" "$TIER"
  [ "$output" = "session" ]
}

@test "tier: branch when the marker names a folder that is gone" {
  write_marker "$TEST_TEMP_DIR/gone"
  tier_of
  [ "$output" = "branch" ]
}

@test "tier: says nothing on stderr" {
  write_marker "$TOPIC"
  tier_of
  [ -z "$stderr" ]
}

@test "tier --id: worktree when the marker is set" {
  write_marker "$TOPIC"
  tier_of --id 42
  [ "$status" -eq 0 ]
  [ "$output" = "worktree" ]
}

@test "tier --id: worktree even when a session override outranks the marker" {
  # The bare form answers "session" here, and the path a --id resolution
  # produces comes from the marker. Asking in the wrong form is how the
  # confirmation prompt came to describe a tier that had lost.
  write_marker "$TOPIC"
  write_session_file "$TEST_TEMP_DIR/elsewhere"
  mkdir -p "$TEST_TEMP_DIR/elsewhere"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" "$TIER"
  [ "$output" = "session" ]

  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" "$TIER" --id 42
  [ "$output" = "worktree" ]
}

@test "tier --id: branch when no marker is set" {
  tier_of --id 42
  [ "$status" -eq 0 ]
  [ "$output" = "branch" ]
}

@test "tier --id: branch when the marker names a folder that is gone" {
  write_marker "$TEST_TEMP_DIR/not-there"
  tier_of --id 42
  [ "$output" = "branch" ]
}

@test "tier --id: says nothing on stderr" {
  write_marker "$TOPIC"
  tier_of --id 42
  [ -z "$stderr" ]
}

@test "tier: the --id form and the resolver agree about the folder" {
  # The whole point of the flag: the tier reported and the path resolved must
  # describe the same resolution.
  write_marker "$TOPIC"
  write_session_file "$TEST_TEMP_DIR/elsewhere"
  mkdir -p "$TEST_TEMP_DIR/elsewhere"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" CLAUDE_CODE_SESSION_ID="$SESSION_ID" "$RESOLVER" --id 42
  [ "$output" = "$TOPIC/42" ]
}

@test "tier: a wrong argument form is a usage error" {
  tier_of --id
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"usage"* ]]
}

@test "tier: an unknown flag is a usage error" {
  tier_of --nope 42
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"usage"* ]]
}

# ============================================================================
# Writing and clearing the marker
# ============================================================================

@test "--worktree writes the marker and prints its path" {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --worktree "$TOPIC"
  [ "$status" -eq 0 ]
  [ "$output" = "$MARKER" ]
  [ "$(cat "$MARKER")" = "$TOPIC" ]
  [[ "$stderr" == *"$TOPIC"* ]]
}

@test "--worktree needs no session id" {
  run --separate-stderr env -u CLAUDE_CODE_SESSION_ID \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --worktree "$TOPIC"
  [ "$status" -eq 0 ]
}

@test "--worktree stores the canonical path, not the spelling" {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --worktree "$TOPIC/../topic"
  [ "$(cat "$MARKER")" = "$TOPIC" ]
}

@test "--worktree refuses a relative path" {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --worktree "topic"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not an absolute path"* ]]
  [ ! -e "$MARKER" ]
}

@test "--worktree refuses a folder that does not exist" {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --worktree "$TEST_TEMP_DIR/not-there"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not an existing directory"* ]]
  [ ! -e "$MARKER" ]
}

@test "--worktree outside a git repository is refused" {
  local outside
  outside="$(mktemp -d)"
  cd "$outside"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --worktree "$TOPIC"
  local st="$status" err="$stderr"
  cd "$TEST_TEMP_DIR"
  rm -rf "$outside"
  [ "$st" -eq 1 ]
  [[ "$err" == *"worktree root"* ]]
}

@test "--worktree takes exactly one folder" {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --worktree "$TOPIC" extra
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"exactly one folder"* ]]
}

@test "--worktree with no folder errors" {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --worktree
  [ "$status" -eq 1 ]
}

@test "a second --worktree replaces the first" {
  local other="$TEST_TEMP_DIR/other"
  mkdir -p "$other"
  "${CLAUDE_ENV_RESET[@]}" MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --worktree "$TOPIC" >/dev/null 2>&1
  "${CLAUDE_ENV_RESET[@]}" MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --worktree "$other" >/dev/null 2>&1
  [ "$(cat "$MARKER")" = "$other" ]
}

@test "--clear --worktree removes the marker and says so" {
  write_marker "$TOPIC"
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --clear --worktree
  [ "$status" -eq 0 ]
  [ ! -e "$MARKER" ]
  [[ "$stderr" == *"cleared"* ]]
}

@test "--clear --worktree with nothing set succeeds and says so" {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --clear --worktree
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"no folder marker"* ]]
}

@test "--clear --worktree leaves the session override alone" {
  local sess="$TEST_TEMP_DIR/session-folder"
  mkdir -p "$sess"
  write_session_file "$sess"
  write_marker "$TOPIC"
  "${CLAUDE_ENV_RESET[@]}" MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --clear --worktree >/dev/null 2>&1
  [ -f "$SESSIONS_DIR/${SESSION_ID}.json" ]
}

@test "--clear --worktree rejects a third argument" {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" \
    MY_CLAUDE_SKILLS_CONFIG="$CFG" "$WRITER" --clear --worktree extra
  [ "$status" -eq 1 ]
}

@test "--clear alone still clears the session, not the marker" {
  local sess="$TEST_TEMP_DIR/session-folder"
  mkdir -p "$sess"
  write_session_file "$sess"
  write_marker "$TOPIC"
  "${CLAUDE_ENV_RESET[@]}" MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    CLAUDE_CODE_SESSION_ID="$SESSION_ID" "$WRITER" --clear >/dev/null 2>&1
  [ -f "$MARKER" ]
  [ ! -f "$SESSIONS_DIR/${SESSION_ID}.json" ]
}

@test "--help names both modes" {
  run --separate-stderr "${CLAUDE_ENV_RESET[@]}" "$WRITER" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--worktree"* ]]
  [[ "$output" == *"--clear"* ]]
}

# ============================================================================
# The working files land where the marker says
# ============================================================================

@test "end to end: every working-file type lands under the marker" {
  # --separate-stderr because the resolver names the folder it chose on every
  # run, and a merged stream would put that line ahead of the path.
  local t
  write_marker "$TOPIC"
  for t in notes questions scratchpads commit-msgs; do
    run --separate-stderr "${CLAUDE_ENV_RESET[@]}" MY_CLAUDE_SKILLS_CONFIG="$CFG" \
      "$PROJECT_ROOT/skills/issue-context/target-path.sh" --type "$t" --description "demo"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == "$TOPIC/$t/"* ]]
  done
}
