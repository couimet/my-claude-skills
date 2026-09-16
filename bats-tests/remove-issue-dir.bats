#!/usr/bin/env bats
#
# Tests for skills/cleanup-issue/remove-issue-dir.sh — safely removes a work
# item's working directory after validating the ID and the folder it was
# handed.
#
# The script no longer builds the path. The caller resolves it through
# get-issue-folder-path.sh --id and passes it in, so the directory the user
# confirmed is the directory that is removed under every tier. These tests
# therefore hand it folders directly, including roots that are nothing like a
# .claude-work tree, which is what a CLAUDE_WORK_FOLDER marker produces.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/cleanup-issue/remove-issue-dir.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  # A realistic .claude-work/issues/ tree for the branch-tier cases.
  mkdir -p "$TEST_TEMP_DIR/.claude-work/issues"
  BASE="$TEST_TEMP_DIR/.claude-work"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# ============================================================================
# Usage errors
# ============================================================================

@test "missing arguments prints usage error" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R002"* ]]
}

@test "single argument prints usage error" {
  run "$SCRIPT" "$BASE/issues/42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R002"* ]]
}

@test "the old <base> <id> form is a usage error, not a deletion" {
  # A caller that was not migrated must fail loudly rather than removing
  # whatever its second argument happens to name.
  mkdir -p "$BASE/issues/42"
  run "$SCRIPT" "$BASE" "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R002"* ]]
  [ -d "$BASE/issues/42" ]
}

@test "a third argument that is not --id is a usage error" {
  run "$SCRIPT" "$BASE/issues/42" "--identifier" "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R002"* ]]
}

# ============================================================================
# Folder validation
# ============================================================================

@test "rejects a relative folder" {
  mkdir -p "$TEST_TEMP_DIR/42"
  cd "$TEST_TEMP_DIR"
  run "$SCRIPT" "42" --id "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R002"* ]]
}

@test "rejects a folder whose last component is not the ID" {
  mkdir -p "$BASE/issues/42"
  run "$SCRIPT" "$BASE/issues" --id "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
  [ -d "$BASE/issues/42" ]
}

@test "accepts a trailing slash on the folder" {
  mkdir -p "$BASE/issues/42"
  run "$SCRIPT" "$BASE/issues/42/" --id "42"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE/issues/42" ]
  [ ! -d "$BASE/issues/42" ]
}

# ============================================================================
# ID validation
# ============================================================================

@test "rejects dot-only ID (.)" {
  run "$SCRIPT" "$BASE/issues/." --id "."
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

@test "rejects dot-dot ID (..)" {
  run "$SCRIPT" "$BASE/issues/.." --id ".."
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

@test "rejects ID with slash" {
  run "$SCRIPT" "$BASE/issues/foo/bar" --id "foo/bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

@test "rejects ID with space" {
  run "$SCRIPT" "$BASE/issues/foo bar" --id "foo bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

@test "rejects ID starting with hyphen" {
  run "$SCRIPT" "$BASE/issues/-foo" --id "-foo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

@test "rejects ID with shell metacharacters" {
  run "$SCRIPT" "$BASE/issues/x" --id '$(whoami)'
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

@test "rejects empty ID" {
  run "$SCRIPT" "$BASE/issues/x" --id ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
}

# ============================================================================
# Reserved category names
# ============================================================================

@test "refuses a reserved category name whatever the folder looks like" {
  # Under a marker, and under an empty segment, the category directories are
  # siblings of work-item folders, so the refusal cannot be tied to a setting.
  mkdir -p "$BASE/issues/notes"
  run "$SCRIPT" "$BASE/issues/notes" --id "notes"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R001"* ]]
  [ -d "$BASE/issues/notes" ]
}

@test "refuses every reserved category name" {
  local name
  for name in notes questions scratchpads commit-msgs; do
    mkdir -p "$TEST_TEMP_DIR/topic/$name"
    run "$SCRIPT" "$TEST_TEMP_DIR/topic/$name" --id "$name"
    [ "$status" -eq 1 ]
    [ -d "$TEST_TEMP_DIR/topic/$name" ]
  done
}

# ============================================================================
# Successful removals
# ============================================================================

@test "removes an existing directory and prints its path" {
  mkdir -p "$BASE/issues/42/scratchpads"
  touch "$BASE/issues/42/scratchpads/0001-plan.txt"

  run "$SCRIPT" "$BASE/issues/42" --id "42"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE/issues/42" ]
  [ ! -d "$BASE/issues/42" ]
}

@test "idempotent: succeeds when the directory does not exist" {
  [ ! -d "$BASE/issues/99" ]

  run "$SCRIPT" "$BASE/issues/99" --id "99"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE/issues/99" ]
}

@test "idempotent: succeeds when the parent does not exist either" {
  rm -rf "$BASE/issues"

  run "$SCRIPT" "$BASE/issues/42" --id "42"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE/issues/42" ]
}

@test "accepts alphanumeric and dot-hyphen IDs" {
  mkdir -p "$BASE/issues/rfc-auth-v2.test/notes"

  run "$SCRIPT" "$BASE/issues/rfc-auth-v2.test" --id "rfc-auth-v2.test"
  [ "$status" -eq 0 ]
  [ ! -d "$BASE/issues/rfc-auth-v2.test" ]
}

@test "removes a folder under a non-default segment the caller resolved" {
  mkdir -p "$BASE/work/42"

  run "$SCRIPT" "$BASE/work/42" --id "42"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE/work/42" ]
  [ ! -d "$BASE/work/42" ]
}

@test "removes a folder directly under the root when the segment is empty" {
  mkdir -p "$BASE/42"

  run "$SCRIPT" "$BASE/42" --id "42"
  [ "$status" -eq 0 ]
  [ ! -d "$BASE/42" ]
}

@test "removes a marker folder that is nowhere near a .claude-work tree" {
  # This is the case the old contract could not express: under a worktree
  # marker the work item lives at <marker>/<ID>, with no .claude-work and no
  # segment anywhere in the path.
  mkdir -p "$TEST_TEMP_DIR/topic/42/notes"
  touch "$TEST_TEMP_DIR/topic/42/active-plan"

  run "$SCRIPT" "$TEST_TEMP_DIR/topic/42" --id "42"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/topic/42" ]
  [ ! -d "$TEST_TEMP_DIR/topic/42" ]
}

# ============================================================================
# Symlink guard
# ============================================================================

@test "refuses a work-item directory symlinked somewhere else" {
  mkdir -p "$TEST_TEMP_DIR/outside"
  touch "$TEST_TEMP_DIR/outside/keep-me"
  ln -s "$TEST_TEMP_DIR/outside" "$BASE/issues/escape-hatch"

  run "$SCRIPT" "$BASE/issues/escape-hatch" --id "escape-hatch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R002"* ]]
  [ -f "$TEST_TEMP_DIR/outside/keep-me" ]
}

# Regression: the guard used to compare the resolved path's basename to the
# ID, which a link named 42 pointing at a directory named 42 satisfies. rm -rf
# then removed the link, left the files, and exited 0, so the run reported a
# cleanup that had not happened.
@test "refuses a symlink whose target's last component is also the ID" {
  mkdir -p "$TEST_TEMP_DIR/outside/42"
  touch "$TEST_TEMP_DIR/outside/42/keep-me"
  ln -s "$TEST_TEMP_DIR/outside/42" "$BASE/issues/42"

  run "$SCRIPT" "$BASE/issues/42" --id "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R002"* ]]
  [ -L "$BASE/issues/42" ]
  [ -f "$TEST_TEMP_DIR/outside/42/keep-me" ]
}

# A dangling link is not the absent-directory case: something put a link where
# a work-item directory belongs, and reporting an idempotent success over it
# would say the cleanup examined a directory nobody ever looked at.
@test "refuses a dangling symlink rather than reporting an idempotent success" {
  ln -s "$TEST_TEMP_DIR/never-existed" "$BASE/issues/42"

  run "$SCRIPT" "$BASE/issues/42" --id "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R002"* ]]
  [ -L "$BASE/issues/42" ]
}

@test "a symlinked parent is fine: only the last component is checked" {
  mkdir -p "$BASE/real/42"
  ln -s "$BASE/real" "$BASE/link"

  run "$SCRIPT" "$BASE/link/42" --id "42"
  [ "$status" -eq 0 ]
  [ ! -d "$BASE/real/42" ]
}

# ============================================================================
# Removal failure
# ============================================================================

# rm -rf succeeds on a directory this process owns even after a chmod, so the
# tool is stubbed rather than the filesystem permissions changed. See
# _stub_failing in test_helper.bash: a stub is the only way into an error
# branch guarding a command that a permission change does not make fail.
@test "a removal that fails is reported rather than counted as done" {
  mkdir -p "$BASE/issues/42"
  local stub_path
  stub_path="$(_stub_failing "$TEST_TEMP_DIR/badrm" rm)"

  run env PATH="$stub_path" "$SCRIPT" "$BASE/issues/42" --id "42"
  [ "$status" -eq 2 ]
  [[ "$output" == *"R003"* ]]
  [[ "$output" == *"failed to remove"* ]]
  # Still on disk. A caller reading the printed path as "this is gone" would be
  # wrong, which is why the branch exits non-zero instead of falling through to
  # the print.
  [ -d "$BASE/issues/42" ]
}
