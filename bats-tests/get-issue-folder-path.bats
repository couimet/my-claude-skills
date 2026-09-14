#!/usr/bin/env bats
#
# Tests for skills/issue-context/get-issue-folder-path.sh — prints the
# .claude-work/ folder that holds a work item's files, from an explicit
# identifier (--id) or inferred from the current branch. Every test runs in a
# fresh git repo with MY_CLAUDE_SKILLS_CONFIG pointed at a temp settings file.

# `run --separate-stderr` is a flagged run, which bats guarantees only from
# 1.5.0 onward. Declaring the floor turns the BW02 warning into a checked
# requirement; CI pins bats 1.14.0 (.github/workflows/ci.yml). The floor reads
# 1.7.0 rather than 1.5.0 because bats_require_minimum_version is itself a
# 1.7.0 command: asking for 1.5.0 names two versions, 1.5.x and 1.6.x, that
# cannot resolve the line making the request, so the suite fails while loading
# on exactly the versions the declaration claims to allow.
bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/get-issue-folder-path.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  git checkout -q -B main
  # Default empty config — every key falls back to the built-in defaults.
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# Run the resolver with MY_CLAUDE_SKILLS_CONFIG pointing at the given config.
#
# --separate-stderr, so $output is the resolver's single stdout line and
# $stderr holds its reports and the settings loader's warnings. The resolver
# reports the folder it chose on every run (issues/267); without the flag that
# line would be folded into $output and every exact-equality assertion below
# would be asserting on two lines.
# -u CLAUDE_CODE_SESSION_ID: a bats run inherits the environment of whoever
# started it, and a Claude Code session exports a real session id. These tests
# assert branch-derived placement, so the session must be absent rather than
# whatever the developer happens to be running under.
folder_with_config() {
  run --separate-stderr env -u CLAUDE_CODE_SESSION_ID \
    MY_CLAUDE_SKILLS_CONFIG="$1" "$SCRIPT" "${@:2}"
}

# ============================================================================
# --id resolution
# ============================================================================

@test "--id 42 → numeric folder under default issues segment" {
  folder_with_config "$CFG" --id 42
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42" ]
}

@test "--id PROJ-123 → key-shaped folder under default issues segment" {
  folder_with_config "$CFG" --id PROJ-123
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/PROJ-123" ]
}

@test "--id with a non-default segment → folder under that segment" {
  local cfg="$TEST_TEMP_DIR/nondefault.json"
  printf '%s' '{"segment":"work"}' > "$cfg"
  folder_with_config "$cfg" --id 42
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/work/42" ]
}

@test "--id with an omitted (empty) segment → no segment directory" {
  local cfg="$TEST_TEMP_DIR/empty-seg.json"
  printf '%s' '{"segment":""}' > "$cfg"
  folder_with_config "$cfg" --id 42
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/42" ]
}

@test "--id does not create the directory" {
  folder_with_config "$CFG" --id 42
  [ ! -d "$TEST_TEMP_DIR/.claude-work/issues/42" ]
}

@test "--id with an unsafe identifier errors" {
  folder_with_config "$CFG" --id ".hidden"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not usable"* ]]
}

# ============================================================================
# Branch inference
# ============================================================================

@test "issues/42 branch (no --id) → issues segment folder" {
  git checkout -q -b issues/42
  folder_with_config "$CFG"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42" ]
}

@test "issues/PROJ-123-add-config branch → key-shaped folder (new key-shaped row)" {
  git checkout -q -b issues/PROJ-123-add-config
  folder_with_config "$CFG"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/PROJ-123" ]
}

@test "PROJ-123-add-config branch (no issues/ prefix) → key-shaped folder (new top-level row)" {
  git checkout -q -b PROJ-123-add-config
  folder_with_config "$CFG"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/PROJ-123" ]
}

@test "main branch → flat root, no segment" {
  folder_with_config "$CFG"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
}

# ============================================================================
# Config plumbing
# ============================================================================

@test "override wins over a config at the HOME default path" {
  local home="$TEST_TEMP_DIR/home"
  mkdir -p "$home/.my-claude-skills"
  printf '%s' '{"segment":"homeval"}' > "$home/.my-claude-skills/settings.json"
  local cfg="$TEST_TEMP_DIR/override.json"
  printf '%s' '{"segment":"overrideval"}' > "$cfg"
  git checkout -q -b issues/42
  run --separate-stderr env -u CLAUDE_CODE_SESSION_ID HOME="$home" MY_CLAUDE_SKILLS_CONFIG="$cfg" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/overrideval/42" ]
}

@test "malformed config → warning, falls back to default segment" {
  local cfg="$TEST_TEMP_DIR/malformed.json"
  printf '%s' '{"segment":' > "$cfg"
  folder_with_config "$cfg" --id 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"warning"* ]]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42" ]
}

# ============================================================================
# Unsafe segment cannot escape the root
# ============================================================================

@test "segment containing a slash falls back to default and cannot escape" {
  local cfg="$TEST_TEMP_DIR/slash-seg.json"
  printf '%s' '{"segment":"work/../x"}' > "$cfg"
  folder_with_config "$cfg" --id 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"warning"* ]]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42" ]
  [[ "$output" != *"/work/../x/"* ]]
}

@test "dotdot segment falls back to default and cannot escape" {
  local cfg="$TEST_TEMP_DIR/dotdot-seg.json"
  printf '%s' '{"segment":".."}' > "$cfg"
  folder_with_config "$cfg" --id 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"warning"* ]]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42" ]
}

# ============================================================================
# identifierCase folding
# ============================================================================

@test "--id proj-1234 → folder carries the folded identifier" {
  folder_with_config "$CFG" --id proj-1234
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/PROJ-1234" ]
}

@test "lowercase branch and --id resolve to one folder" {
  # The defect issues/262 is about: one ticket, two entry points, two folders.
  git checkout -q -b issues/proj-1234
  folder_with_config "$CFG"
  local from_branch="$output"
  folder_with_config "$CFG" --id PROJ-1234
  [ "$status" -eq 0 ]
  [ "$output" = "$from_branch" ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/PROJ-1234" ]
}

@test "--id proj-1234 under preserve → folder keeps the given case" {
  local cfg="$TEST_TEMP_DIR/preserve.json"
  printf '%s' '{"identifierCase":"preserve"}' > "$cfg"
  folder_with_config "$cfg" --id proj-1234
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/proj-1234" ]
}

@test "--id for a numeric work item is unaffected by folding" {
  folder_with_config "$CFG" --id 262
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/262" ]
}

# ============================================================================
# Session folder override (issues/267)
#
# These tests run the resolver with --separate-stderr, so $output is the single
# stdout line and $stderr holds the reports. Every case asserts the stdout line
# count as well as its value: the whole point of routing reports to stderr is
# that a caller capturing stdout with command substitution gets a path and
# nothing else.
# ============================================================================

SESSION_ID="06cb4128-c112-4696-bddb-3a52d1684a20"

# Run the resolver with a session id in the environment.
folder_with_session() {
  run --separate-stderr env \
    MY_CLAUDE_SKILLS_CONFIG="$1" \
    CLAUDE_CODE_SESSION_ID="$2" \
    "$SCRIPT" "${@:3}"
}

# Write a session file for SESSION_ID pointing at <folder>, under the sessions
# directory beside the config file.
write_session_file() {
  local folder="$1" name="${2:-${SESSION_ID}.json}"
  mkdir -p "$TEST_TEMP_DIR/sessions"
  printf '{"version":1,"folder":"%s","session_id":"%s"}' \
    "$folder" "$SESSION_ID" > "$TEST_TEMP_DIR/sessions/$name"
}

@test "override: no session file → branch-derived placement, unchanged" {
  git checkout -q -b issues/42
  folder_with_session "$CFG" "$SESSION_ID"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42" ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$stderr" == *"using $TEST_TEMP_DIR/.claude-work/issues/42"* ]]
  [[ "$stderr" != *"override"* ]]
}

@test "override: valid session file wins over the branch" {
  mkdir -p "$TEST_TEMP_DIR/my-topic"
  write_session_file "$TEST_TEMP_DIR/my-topic"
  git checkout -q -b issues/42
  folder_with_session "$CFG" "$SESSION_ID"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/my-topic" ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$stderr" == *"using $TEST_TEMP_DIR/my-topic"* ]]
}

@test "override: valid session file also wins over flat placement" {
  mkdir -p "$TEST_TEMP_DIR/my-topic"
  write_session_file "$TEST_TEMP_DIR/my-topic"
  folder_with_session "$CFG" "$SESSION_ID"
  [ "$output" = "$TEST_TEMP_DIR/my-topic" ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "override: a file with no slug in its name resolves the same" {
  mkdir -p "$TEST_TEMP_DIR/my-topic"
  write_session_file "$TEST_TEMP_DIR/my-topic" "${SESSION_ID}--some-work.json"
  folder_with_session "$CFG" "$SESSION_ID"
  [ "$output" = "$TEST_TEMP_DIR/my-topic" ]
}

@test "override: another session's file is not read" {
  mkdir -p "$TEST_TEMP_DIR/my-topic"
  write_session_file "$TEST_TEMP_DIR/my-topic" "some-other-session.json"
  folder_with_session "$CFG" "$SESSION_ID"
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [[ "$stderr" != *"override"* ]]
}

@test "override: --id bypasses it and says so" {
  mkdir -p "$TEST_TEMP_DIR/my-topic"
  write_session_file "$TEST_TEMP_DIR/my-topic"
  folder_with_session "$CFG" "$SESSION_ID" --id 42
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42" ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$stderr" == *"bypassed"* ]]
  [[ "$stderr" == *"--id names a work item explicitly"* ]]
}

@test "override: a folder that no longer exists is ignored and reported" {
  write_session_file "$TEST_TEMP_DIR/deleted-topic"
  git checkout -q -b issues/42
  folder_with_session "$CFG" "$SESSION_ID"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42" ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$stderr" == *"not an existing directory"* ]]
}

@test "override: a relative path is refused" {
  write_session_file "my-topic"
  folder_with_session "$CFG" "$SESSION_ID"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [[ "$stderr" == *"not an absolute path"* ]]
}

@test "override: a path outside the repository is refused and named" {
  local outside
  outside="$(mktemp -d)"
  outside="$(cd "$outside" && pwd -P)"
  write_session_file "$outside"
  folder_with_session "$CFG" "$SESSION_ID"
  rm -rf "$outside"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$stderr" == *"outside this repository"* ]]
}

@test "override: a path escaping through .. is refused" {
  # The literal string sits under the repo; the physical path does not.
  local escaping="$TEST_TEMP_DIR/../$(basename "$TEST_TEMP_DIR")-escape"
  mkdir -p "$escaping"
  write_session_file "$escaping"
  folder_with_session "$CFG" "$SESSION_ID"
  rm -rf "$escaping"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [[ "$stderr" == *"outside this repository"* ]]
}

@test "override: a malformed session file is ignored and reported" {
  mkdir -p "$TEST_TEMP_DIR/sessions"
  printf '%s' '{"version":1,"folder":' > "$TEST_TEMP_DIR/sessions/${SESSION_ID}.json"
  folder_with_session "$CFG" "$SESSION_ID"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$stderr" == *"unreadable or malformed"* ]]
}

@test "override: an unrecognised version is ignored and reported" {
  mkdir -p "$TEST_TEMP_DIR/my-topic" "$TEST_TEMP_DIR/sessions"
  printf '{"version":99,"folder":"%s/my-topic"}' "$TEST_TEMP_DIR" \
    > "$TEST_TEMP_DIR/sessions/${SESSION_ID}.json"
  folder_with_session "$CFG" "$SESSION_ID"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [[ "$stderr" == *"unrecognised version"* ]]
}

@test "override: two files for one session are refused and reported" {
  mkdir -p "$TEST_TEMP_DIR/my-topic"
  write_session_file "$TEST_TEMP_DIR/my-topic"
  write_session_file "$TEST_TEMP_DIR/my-topic" "${SESSION_ID}--second.json"
  folder_with_session "$CFG" "$SESSION_ID"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$stderr" == *"more than one session file"* ]]
}

@test "override: the sessions directory follows MY_CLAUDE_SKILLS_CONFIG" {
  # A config elsewhere means a sessions directory elsewhere, so a file beside
  # the default config must not be found.
  mkdir -p "$TEST_TEMP_DIR/my-topic" "$TEST_TEMP_DIR/elsewhere"
  write_session_file "$TEST_TEMP_DIR/my-topic"
  local other="$TEST_TEMP_DIR/elsewhere/settings.json"
  printf '%s' '{}' > "$other"
  folder_with_session "$other" "$SESSION_ID"
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [[ "$stderr" != *"override"* ]]
}

@test "override: the folder is not created by resolving it" {
  write_session_file "$TEST_TEMP_DIR/never-made"
  folder_with_session "$CFG" "$SESSION_ID"
  [ ! -d "$TEST_TEMP_DIR/never-made" ]
}

@test "override: the repository root itself is inside the repository" {
  write_session_file "$TEST_TEMP_DIR"
  folder_with_session "$CFG" "$SESSION_ID"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR" ]
}

@test "override: a sibling path sharing the root's name prefix is refused" {
  # "$TEST_TEMP_DIR-sibling" starts with the root string but is not under it.
  local sibling="${TEST_TEMP_DIR}-sibling"
  mkdir -p "$sibling"
  write_session_file "$sibling"
  folder_with_session "$CFG" "$SESSION_ID"
  rm -rf "$sibling"
  [ "$output" = "$TEST_TEMP_DIR/.claude-work" ]
  [[ "$stderr" == *"outside this repository"* ]]
}
