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
  # Pin settings to an empty object so the loader uses the built-in defaults
  # (segment "issues") regardless of the developer's real settings file.
  export MY_CLAUDE_SKILLS_CONFIG="$TEST_TEMP_DIR/settings.json"
  printf '{}\n' > "$MY_CLAUDE_SKILLS_CONFIG"
}

# Overwrite the pinned settings file with a custom segment ("" = flat layout).
set_segment() {
  printf '{"segment":"%s"}\n' "$1" > "$MY_CLAUDE_SKILLS_CONFIG"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# --- Helpers ---

# Export a mock `gh` that answers from fixture env vars:
#   GH_PR_ROWS        — TAB-separated rows: head<TAB>base<TAB>state<TAB>number
#   GH_CLOSED_ISSUES  — one closed issue number per line
# The script must gather both inventories via gh api --paginate (complete
# pagination, no --limit cap): any call without --paginate or with a
# different URL fails, pinning the complete-inventory contract. gh api
# substitutes {owner}/{repo} from the repo remote, so the mock matches the
# templated URLs the script passes.
mock_gh() {
  gh() {
    if [[ "$1" == "api" && "$2" == "--paginate" ]]; then
      case "$3" in
        "repos/{owner}/{repo}/pulls?state=all&per_page=100")
          if [ -n "${GH_PR_ROWS:-}" ]; then
            printf '%s\n' "$GH_PR_ROWS"
          fi
          ;;
        "repos/{owner}/{repo}/issues?state=closed&per_page=100")
          if [ -n "${GH_CLOSED_ISSUES:-}" ]; then
            printf '%s\n' "$GH_CLOSED_ISSUES"
          fi
          ;;
        *)
          return 1
          ;;
      esac
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
# Suffixed issue branches
# ============================================================================

@test "closed issue with open PR head issues/42-fix → not deletable" {
  mkdir -p "$BASE/issues/42"
  export GH_CLOSED_ISSUES="42"
  export GH_PR_ROWS=$'issues/42-fix\tmain\tOPEN\t42'
  mock_gh
  run "$SCRIPT" "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
}

@test "closed issue with open PR head issues/42_fix → not deletable" {
  mkdir -p "$BASE/issues/42"
  export GH_CLOSED_ISSUES="42"
  export GH_PR_ROWS=$'issues/42_fix\tmain\tOPEN\t42'
  mock_gh
  run "$SCRIPT" "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
}

@test "closed issue with local branch issues/42-fix → not deletable" {
  mkdir -p "$BASE/issues/42"
  git branch issues/42-fix
  export GH_CLOSED_ISSUES="42"
  mock_gh
  run "$SCRIPT" "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
}

@test "closed issue with local branch issues/42_fix → not deletable" {
  mkdir -p "$BASE/issues/42"
  git branch issues/42_fix
  export GH_CLOSED_ISSUES="42"
  mock_gh
  run "$SCRIPT" "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
}

@test "closed issue with unrelated branch issues/42x → still deletable" {
  mkdir -p "$BASE/issues/42"
  export GH_PR_ROWS=$'issues/42x\tmain\tOPEN\t42'
  export GH_CLOSED_ISSUES="42"
  mock_gh
  run "$SCRIPT" "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETABLE"* ]]
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
  export GH_CLOSED_ISSUES="42"
  export GH_PR_ROWS=$'issues/42\tmain\tOPEN\t42'
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
}

@test "merged PR plus open PR on same issue → not deletable (open PR blocks)" {
  mkdir -p "$BASE/issues/42"
  # One matching PR merged into main while a newer matching PR is still
  # open: active work remains, so the folder must be kept even though the
  # merged-PR criterion alone would report DELETABLE.
  export GH_PR_ROWS=$'issues/42\tmain\tMERGED\t10\nissues/42\tmain\tOPEN\t11'
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
}

@test "matching open PR beyond the first 100 rows → not deletable" {
  mkdir -p "$BASE/issues/42"
  export GH_CLOSED_ISSUES="42"
  # 100 unrelated OPEN rows, then the matching issues/42 row at position
  # 101: the REST pulls API serves 100 records per page, so this row sits
  # beyond the first page and a non-paginated query would miss it, wrongly
  # marking the folder DELETABLE. The mock fails any pulls call without
  # --paginate, so the absence of the "gh pulls query failed" notice proves
  # the script requested complete pagination.
  local tab=$'\t' rows="" i
  for ((i = 100; i < 200; i++)); do
    rows+="issues/$i${tab}main${tab}OPEN${tab}$i"$'\n'
  done
  rows+="issues/42${tab}main${tab}OPEN${tab}42"
  export GH_PR_ROWS="$rows"
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
  [[ "$output" != *"gh pulls query failed"* ]]
}

@test "closed issue beyond the first 100 records → DELETABLE" {
  mkdir -p "$BASE/issues/42"
  # 100 unrelated closed issues, then issue 42: a single-page query would
  # return only the first 100 records and the sweep would miss the folder.
  local issues="" i
  for ((i = 100; i < 200; i++)); do
    issues+="$i"$'\n'
  done
  issues+="42"
  export GH_CLOSED_ISSUES="$issues"
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETABLE"* ]]
}

# ============================================================================
# Key-shaped and slug identifiers (branchPatterns, not literal issues/*)
# ============================================================================

@test "merged PR on key-shaped head → key folder is DELETABLE, not skipped" {
  mkdir -p "$BASE/issues/PROJ-123"
  export GH_PR_ROWS=$'PROJ-123-fix\tmain\tMERGED\t77'
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  local expected
  expected="$(printf 'DELETABLE\t%s/issues/PROJ-123\t%s' "$BASE" "merged PR into main (PR #77)")"
  [[ "$output" == *"$expected"* ]]
  [[ "$output" != *"Skipped"* ]]
}

@test "open PR on slug head blocks deletion of slug folder" {
  mkdir -p "$BASE/issues/rfc-auth"
  export GH_PR_ROWS=$'issues/rfc-auth\tmain\tOPEN\t9'
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" != *"DELETABLE"* ]]
  [[ "$output" != *"Skipped"* ]]
}

@test "hidden entry under issues/ → Skipped line, no DELETABLE, exit 0" {
  mkdir -p "$BASE/issues/.hidden"
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped: .hidden (not a valid work-item identifier, not checked)"* ]]
  [[ "$output" != *"DELETABLE"* ]]
}

# ============================================================================
# Configurable segment
# ============================================================================

@test "non-default segment → classifies folders under <base>/<segment>" {
  mkdir -p "$BASE/work/42"
  set_segment "work"
  export GH_PR_ROWS=$'issues/42\tmain\tMERGED\t42'
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  local expected
  expected="$(printf 'DELETABLE\t%s/work/42\t%s' "$BASE" "merged PR into main (PR #42)")"
  [[ "$output" == *"$expected"* ]]
}

@test "empty segment → classifies folders under <base>, never the category dirs" {
  mkdir -p "$BASE/42" "$BASE/notes" "$BASE/questions"
  set_segment ""
  export GH_PR_ROWS=$'issues/42\tmain\tMERGED\t42'
  mock_gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  local expected
  expected="$(printf 'DELETABLE\t%s/42\t%s' "$BASE" "merged PR into main (PR #42)")"
  [[ "$output" == *"$expected"* ]]
  [[ "$output" != *"/notes"* ]]
  [[ "$output" != *"/questions"* ]]
}

# ============================================================================
# gh availability and failures
# ============================================================================

@test "gh not on PATH → notice, exit 0, no DELETABLE lines" {
  mkdir -p "$BASE/issues/42"

  # Build a minimal PATH containing only bash. The script's shebang is
  # /usr/bin/env bash, so env resolves bash through PATH. No gh symlink means
  # `command -v gh` fails even when gh shares a directory with bash (CI).
  # The gh-missing guard exits before git or any other binary is needed.
  local path_bin
  path_bin="$TEST_TEMP_DIR/path-bin"
  mkdir -p "$path_bin"
  ln -s "$(command -v bash)" "$path_bin/bash"

  # Drop any exported mock so gh is genuinely unavailable to the script.
  unset -f gh || true

  run env "PATH=$path_bin" "$SCRIPT" "$BASE"

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

@test "gh pulls query fails while closed-issue fixture reports 42 → exit 0, no DELETABLE lines" {
  mkdir -p "$BASE/issues/42"

  gh() {
    if [[ "$1" == "api" && "$2" == "--paginate" ]] \
        && [[ "$3" == "repos/{owner}/{repo}/issues?state=closed&per_page=100" ]]; then
      printf '42\n'
    else
      return 1
    fi
  }
  export -f gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"gh pulls query failed"* ]]
  [[ "$output" != *"DELETABLE"* ]]
}

@test "gh issues query fails while merged-PR fixture exists → exit 0, no DELETABLE lines" {
  mkdir -p "$BASE/issues/42"

  gh() {
    if [[ "$1" == "api" && "$2" == "--paginate" ]] \
        && [[ "$3" == "repos/{owner}/{repo}/pulls?state=all&per_page=100" ]]; then
      printf 'issues/42\tmain\tMERGED\t42\n'
    else
      return 1
    fi
  }
  export -f gh

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"gh issues query failed"* ]]
  [[ "$output" != *"DELETABLE"* ]]
}

@test "git branch fails while closed-issue fixture reports 42 → exit 0, no DELETABLE lines" {
  mkdir -p "$BASE/issues/42"
  export GH_CLOSED_ISSUES="42"
  mock_gh

  git() {
    return 1
  }
  export -f git

  run "$SCRIPT" "$BASE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"git branch failed"* ]]
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
