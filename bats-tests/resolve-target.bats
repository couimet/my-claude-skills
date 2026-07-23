#!/usr/bin/env bats
#
# Tests for skills/rebase-issue/resolve-target.sh — resolves the rebase
# target ref and classifies the mode (normal or stacked).

load test_helper

SCRIPT="$PROJECT_ROOT/skills/rebase-issue/resolve-target.sh"

# Each test runs inside a fresh git repo so marker-file lookups and
# git ls-remote behave deterministically.
setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  cd "$TEST_TEMP_DIR"
  git init --initial-branch=main -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "initial commit"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# --- Helpers ---

# Write content to a file, creating parent directories as needed.
write_file() {
  local path="$1"
  local content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$content" > "$path"
}

# Create a bare repo and add it as origin, then push a named branch to it.
# Used by tests that need a real remote for the "remote ref exists" path.
setup_remote_with_branch() {
  local branch_name="$1"
  local bare_repo="$TEST_TEMP_DIR/bare-remote.git"

  git init --bare -q "$bare_repo"
  git remote add origin "$bare_repo"

  # Push the named branch (create it first if needed).
  if ! git rev-parse --verify "$branch_name" >/dev/null 2>&1; then
    git branch "$branch_name" main
  fi
  git push -q origin "$branch_name" 2>/dev/null
}

# ============================================================================
# Argument validation
# ============================================================================

@test "no arguments → error T001" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T001"* ]]
  [[ "$output" == *"expected 1-2 arguments, got 0"* ]]
}

@test "three arguments → error T001" {
  run "$SCRIPT" "42" "origin/main" "extra"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T001"* ]]
}

@test "empty issue number → error T002" {
  run "$SCRIPT" "" "origin/main"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T002"* ]]
  [[ "$output" == *"invalid issue number"* ]]
}

@test "issue number with slash → error T002" {
  run "$SCRIPT" "42/evil" "origin/main"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T002"* ]]
  [[ "$output" == *"invalid issue number"* ]]
}

@test "usage text printed on argument error" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "claude-work-root.sh not found → error T003" {
  local claude_root_script="$PROJECT_ROOT/skills/issue-context/claude-work-root.sh"

  # Temporarily move the script aside so resolve-target.sh cannot find it.
  mv "$claude_root_script" "${claude_root_script}.bak"

  run "$SCRIPT" "42" "origin/main"
  local actual_status="$status"

  # Restore immediately so other tests are not affected.
  mv "${claude_root_script}.bak" "$claude_root_script"

  [ "$actual_status" -eq 1 ]
  [[ "$output" == *"T003"* ]]
}

# ============================================================================
# Explicit target — resolution
# ============================================================================

@test "explicit target is used verbatim" {
  run "$SCRIPT" "42" "origin/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=origin/main"* ]]
}

@test "explicit target with issues/ prefix is preserved" {
  run "$SCRIPT" "42" "issues/200"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=issues/200"* ]]
}

@test "explicit target with short ref is preserved" {
  run "$SCRIPT" "42" "main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=main"* ]]
}

@test "explicit target wins over base-branch marker" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "issues/100"

  run "$SCRIPT" "42" "origin/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=origin/main"* ]]
}

@test "explicit empty target treated as unset → falls back to marker" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "issues/100"

  # Set up remote so the marker value is accepted.
  setup_remote_with_branch "issues/100"

  run "$SCRIPT" "42" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=issues/100"* ]]
}

# ============================================================================
# Mode classification
# ============================================================================

@test "explicit issues/200 → MODE=stacked" {
  run "$SCRIPT" "42" "issues/200"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODE=stacked"* ]]
}

@test "explicit issues/123-some-feature → MODE=stacked" {
  run "$SCRIPT" "42" "issues/123-some-feature"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODE=stacked"* ]]
}

@test "explicit origin/main → MODE=normal" {
  run "$SCRIPT" "42" "origin/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODE=normal"* ]]
}

@test "explicit main → MODE=normal" {
  run "$SCRIPT" "42" "main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODE=normal"* ]]
}

@test "issues/foo (non-numeric) → MODE=stacked" {
  run "$SCRIPT" "42" "issues/foo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODE=stacked"* ]]
}

@test "feature/issues/200 → MODE=stacked (any non-main/master target is stacked)" {
  run "$SCRIPT" "42" "feature/issues/200"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODE=stacked"* ]]
}
@test "origin/issues/200 → MODE=stacked" {
  run "$SCRIPT" "42" "origin/issues/200"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODE=stacked"* ]]
}

@test "origin/issues/123-some-feature → MODE=stacked" {
  run "$SCRIPT" "42" "origin/issues/123-some-feature"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODE=stacked"* ]]
}

@test "origin/issues/side-quest (non-numeric) → MODE=stacked" {
  run "$SCRIPT" "42" "origin/issues/side-quest"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODE=stacked"* ]]
}

# ============================================================================
# Auto-resolution: gh pr list
# ============================================================================

@test "gh pr list returns base ref → TARGET=origin/<base>, MODE=stacked, marker updated" {
  setup_remote_with_branch "main"

  gh() {
    if [[ "$1" == "pr" && "$2" == "list" ]]; then
      echo 'issues/233-layer-one'
    fi
  }
  export -f gh

  run "$SCRIPT" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=origin/issues/233-layer-one"* ]]
  [[ "$output" == *"MODE=stacked"* ]]

  local marker_file="$TEST_TEMP_DIR/.claude-work/issues/42/base-branch"
  [ -f "$marker_file" ]
  [ "$(cat "$marker_file")" = "origin/issues/233-layer-one" ]
}

@test "gh pr list returns base ref with origin/ prefix → no double prefix" {
  setup_remote_with_branch "main"

  gh() {
    if [[ "$1" == "pr" && "$2" == "list" ]]; then
      echo 'origin/issues/233-layer-one'
    fi
  }
  export -f gh

  run "$SCRIPT" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=origin/issues/233-layer-one"* ]]
  [[ "$output" != *"origin/origin/"* ]]
}

@test "gh pr list returns empty → falls through to marker" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "issues/100"

  setup_remote_with_branch "issues/100"

  gh() {
    return 0
  }
  export -f gh

  run "$SCRIPT" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=issues/100"* ]]
  [[ "$output" == *"MODE=stacked"* ]]
}

@test "gh pr list returns literal null → falls through to marker" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "issues/100"

  setup_remote_with_branch "issues/100"

  gh() {
    echo 'null'
  }
  export -f gh

  run "$SCRIPT" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=issues/100"* ]]
  [[ "$output" == *"MODE=stacked"* ]]
}

@test "gh pr list not available → falls through to marker" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "issues/100"

  setup_remote_with_branch "issues/100"

  run "$SCRIPT" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=issues/100"* ]]
  [[ "$output" == *"MODE=stacked"* ]]
}

# ============================================================================
# Auto-resolution: base-branch marker
# ============================================================================

@test "no marker and no explicit target → fallback to origin/main with MODE=normal" {
  run "$SCRIPT" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=origin/main"* ]]
  [[ "$output" == *"MODE=normal"* ]]
}

@test "marker file missing → fallback to origin/main" {
  run "$SCRIPT" "99"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=origin/main"* ]]
  [[ "$output" == *"MODE=normal"* ]]
}

@test "marker file empty → fallback to origin/main" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" ""

  run "$SCRIPT" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=origin/main"* ]]
}

@test "marker has issues/ branch, remote ref exists → use base-branch, MODE=stacked" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "issues/100"

  setup_remote_with_branch "issues/100"

  run "$SCRIPT" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=issues/100"* ]]
  [[ "$output" == *"MODE=stacked"* ]]
}

@test "marker has origin/issues/100, remote ref exists → TARGET=origin/issues/100, MODE=stacked" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "origin/issues/100"

  setup_remote_with_branch "issues/100"

  run "$SCRIPT" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=origin/issues/100"* ]]
  [[ "$output" == *"MODE=stacked"* ]]
}

@test "marker has issues/ branch, no remote → error T004" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "issues/100"

  # No remote configured — git ls-remote origin will fail.

  run "$SCRIPT" "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T004"* ]]
  [[ "$output" == *"no longer exists on remote"* ]]
}

@test "marker has issues/ branch, remote exists but ref absent → error T004" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "issues/999"

  # Set up remote with a *different* branch so ls-remote succeeds
  # but returns nothing for issues/999.
  setup_remote_with_branch "issues/100"

  run "$SCRIPT" "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T004"* ]]
  [[ "$output" == *"no longer exists on remote"* ]]
}

@test "marker has origin/main base → MODE=normal (not an issues/ ref)" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "origin/main"

  # origin/main always exists in remote (pushed via setup_remote_with_branch).
  setup_remote_with_branch "main"

  run "$SCRIPT" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=origin/main"* ]]
  [[ "$output" == *"MODE=normal"* ]]
}

@test "marker has origin/feature-branch, remote ref exists → use base-branch, MODE=stacked" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "origin/my-feature"

  # Push a non-main feature branch to the remote.
  git branch my-feature main
  setup_remote_with_branch "my-feature"

  run "$SCRIPT" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=origin/my-feature"* ]]
  [[ "$output" == *"MODE=stacked"* ]]
}

@test "marker has origin/feature-branch, remote ref absent → error T004" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "origin/nonexistent"

  # origin exists but does NOT have a branch named "nonexistent".
  setup_remote_with_branch "main"

  run "$SCRIPT" "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T004"* ]]
  [[ "$output" == *"no longer exists on remote"* ]]
}

@test "marker ref matches a tag but not a branch → error T004" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" "issues/100"

  # Create a bare remote and push only a tag (no branch) named issues/100.
  local bare_repo="$TEST_TEMP_DIR/bare-remote.git"
  git init --bare -q "$bare_repo"
  git remote add origin "$bare_repo"

  git tag "issues/100" main
  git push -q origin "refs/tags/issues/100" 2>/dev/null

  run "$SCRIPT" "42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T004"* ]]
  [[ "$output" == *"no longer exists on remote"* ]]
}

# ============================================================================
# Output format
# ============================================================================

@test "output contains exactly two lines: TARGET= and MODE=" {
  run "$SCRIPT" "42" "origin/main"
  [ "$status" -eq 0 ]

  # Count lines of output (excluding stderr merged by run).
  local line_count
  line_count="$(echo "$output" | grep -c .)"
  [ "$line_count" -eq 2 ]
}

@test "TARGET line appears before MODE line" {
  run "$SCRIPT" "42" "issues/200"
  [ "$status" -eq 0 ]

  local first_line
  first_line="$(echo "$output" | head -n1)"
  [[ "$first_line" == "TARGET="* ]]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "non-numeric issue identifier works" {
  run "$SCRIPT" "rfc-auth" "origin/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=origin/main"* ]]
  [[ "$output" == *"MODE=normal"* ]]
}

@test "marker file with trailing newline is handled" {
  local marker_dir="$TEST_TEMP_DIR/.claude-work/issues/42"
  write_file "$marker_dir/base-branch" $'issues/100\n'

  setup_remote_with_branch "issues/100"

  run "$SCRIPT" "42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=issues/100"* ]]
  [[ "$output" == *"MODE=stacked"* ]]
}
