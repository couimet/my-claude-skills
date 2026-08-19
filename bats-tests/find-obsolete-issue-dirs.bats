#!/usr/bin/env bats
#
# Tests for skills/cleanup-issue/find-obsolete-issue-dirs.sh — classifies
# .claude-work/issues/<N>/ folders as DELETABLE based on PR state, closed
# issues, and local branches.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/cleanup-issue/find-obsolete-issue-dirs.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  mkdir -p "$TEST_TEMP_DIR/.claude-work/issues"
  BASE="$TEST_TEMP_DIR/.claude-work"
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

# Export a mock `gh` that answers from fixture env vars:
#   GH_PR_ROWS        — TAB-separated rows: headRefName<TAB>baseRefName<TAB>state<TAB>number
#   GH_CLOSED_ISSUES  — one closed issue number per line
# Any other invocation returns 1.
mock_gh() {
  gh() {
    if [[ "$1" == "pr" && "$2" == "list" ]]; then
      if [ -n "${GH_PR_ROWS:-}" ]; then
        printf '%s\n' "$GH_PR_ROWS"
      fi
    elif [[ "$1" == "issue" && "$2" == "list" ]]; then
      if [ -n "${GH_CLOSED_ISSUES:-}" ]; then
        printf '%s\n' "$GH_CLOSED_ISSUES"
      fi
    else
      return 1
    fi
  }
  export -f gh
}

# Count DELETABLE lines in $output.
count_deletable() {
  printf '%s\n' "$output" | grep -c '^DELETABLE' || true
}

# ============================================================================
# Argument and base validation
# ============================================================================

@test "no arguments → F001, exit 1" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"F001"* ]]
}

@test "two arguments → F001, exit 1" {
  run "$SCRIPT" "$BASE" "extra"
  [ "$status" -eq 1 ]
  [[ "$output" == *"F001"* ]]
}

@test "relative base → F002, exit 1" {
  run "$SCRIPT" ".claude-work"
  [ "$status" -eq 1 ]
  [[ "$output" == *"F002"* ]]
}

@test "base not ending in /.claude-work → F002, exit 1" {
  mkdir -p "$TEST_TEMP_DIR/somewhere"
  run "$SCRIPT" "$TEST_TEMP_DIR/somewhere"
  [ "$status" -eq 1 ]
  [[ "$output" == *"F002"* ]]
}

@test "nonexistent base → F002, exit 1" {
  run "$SCRIPT" "$TEST_TEMP_DIR/does-not-exist"
  [ "$status" -eq 1 ]
  [[ "$output" == *"F002"* ]]
}

# ============================================================================
# Merged PR classification
# ============================================================================

@test "merged PR into main → exactly one DELETABLE line with absolute path and reason" {
  mkdir -p "$BASE/issues/42"
  export GH_PR_ROWS=$'issues/42\tmain\tMERGED\t42'
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  local expected
  expected="$(printf 'DELETABLE\t%s/issues/42\t%s' "$BASE" "merged PR into main (PR #42)")"
  [[ "$output" == *"$expected"* ]]
  [ "$(count_deletable)" -eq 1 ]
}

@test "merged PR with non-main base → not deletable" {
  mkdir -p "$BASE/issues/42"
  export GH_PR_ROWS=$'issues/42\tissues/100\tMERGED\t42'
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
}

# ============================================================================
# Closed-issue classification
# ============================================================================

@test "closed issue, no open PR, no local branch → DELETABLE" {
  mkdir -p "$BASE/issues/42"
  export GH_CLOSED_ISSUES="42"
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  local expected
  expected="$(printf 'DELETABLE\t%s/issues/42\t%s' "$BASE" "issue closed, no open PR, no local branch")"
  [[ "$output" == *"$expected"* ]]
  [ "$(count_deletable)" -eq 1 ]
}

@test "closed issue with local branch issues/42 → not deletable" {
  mkdir -p "$BASE/issues/42"
  git branch issues/42
  export GH_CLOSED_ISSUES="42"
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
}

# ============================================================================
# Non-deletable numeric folders
# ============================================================================

@test "open issue with no PRs → not deletable" {
  mkdir -p "$BASE/issues/42"
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
}

@test "open PR exists → not deletable" {
  mkdir -p "$BASE/issues/42"
  export GH_PR_ROWS=$'issues/42\tmain\tOPEN\t42'
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
}

# ============================================================================
# Non-numeric folders
# ============================================================================

@test "non-numeric folder → Skipped line, no DELETABLE, exit 0" {
  mkdir -p "$BASE/issues/foo"
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped: foo (non-numeric ID, not checked)"* ]]
  [[ "$output" != *"DELETABLE"* ]]
}

# ============================================================================
# gh availability and failures
# ============================================================================

@test "gh not on PATH → notice, exit 0, no DELETABLE lines" {
  mkdir -p "$BASE/issues/42"

  # Learn the real binary locations so we can build a PATH that keeps git
  # but excludes gh.
  local gh_path git_path git_dir restricted_path
  gh_path="$(command -v gh 2>/dev/null || true)"
  git_path="$(command -v git)"
  git_dir="$(dirname "$git_path")"

  # Drop any exported mock so gh is genuinely unavailable to the script.
  unset -f gh || true

  restricted_path="$git_dir:/usr/bin:/bin"
  if [ -n "$gh_path" ]; then
    restricted_path="$(printf '%s' "$restricted_path" | tr ':' '\n' | grep -Fv -- "$(dirname "$gh_path")" | paste -sd: -)"
    if [ -z "$restricted_path" ]; then
      restricted_path="/usr/bin:/bin"
    fi
  fi

  run env "PATH=$restricted_path" "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"gh not available"* ]]
  [[ "$output" != *"DELETABLE"* ]]
}

@test "gh invocation fails → exit 0, no DELETABLE lines" {
  mkdir -p "$BASE/issues/42"

  gh() {
    return 1
  }
  export -f gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
}

# ============================================================================
# Empty directory and output format
# ============================================================================

@test "empty issues dir → exit 0, no output" {
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "DELETABLE line splits on TAB into exactly 3 fields with absolute path" {
  mkdir -p "$BASE/issues/42"
  export GH_PR_ROWS=$'issues/42\tmain\tMERGED\t42'
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]

  local del_line
  del_line="$(printf '%s\n' "$output" | grep '^DELETABLE' | head -n1)"
  IFS=$'\t' read -r -a fields <<< "$del_line"

  [ "${#fields[@]}" -eq 3 ]
  [ "${fields[0]}" = "DELETABLE" ]
  [ "${fields[1]}" = "$BASE/issues/42" ]
  [ "${fields[2]}" = "merged PR into main (PR #42)" ]
}
