#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/skills/start-issue/update-project-status.sh"

setup() {
  MOCK_DIR="$(mktemp -d)"
  export MOCK_DIR

  # Track gh calls for assertions
  export GH_CALLS="$MOCK_DIR/gh-calls"
  touch "$GH_CALLS"

  # Create mock gh
  cat > "$MOCK_DIR/gh" <<'MOCK_SCRIPT'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"

case "$1" in
  auth)
    # Return scopes based on GH_AUTH_SCOPES env var
    echo "Token scopes: ${GH_AUTH_SCOPES:-'gist', 'repo'}"
    ;;
  api)
    if [[ "$*" == *"issue(number:"* ]]; then
      if [ "${GH_QUERY_FAIL:-}" = "true" ]; then
        echo "mock: query failed" >&2
        exit 1
      fi
      # Project items query — return fixture or default empty
      cat "${GH_FIXTURE:-/dev/stdin}"
    elif [[ "$*" == *"updateProjectV2ItemFieldValue"* ]]; then
      # Mutation — fail if GH_MUTATION_FAIL is set
      if [ "${GH_MUTATION_FAIL:-}" = "true" ]; then
        echo "mock: mutation failed" >&2
        exit 1
      fi
    fi
    ;;
  issue)
    if [[ "$*" == *"comment"* ]]; then
      if [ "${GH_COMMENT_FAIL:-}" = "true" ]; then
        echo "mock: comment failed" >&2
        exit 1
      fi
    fi
    ;;
esac
MOCK_SCRIPT
  chmod +x "$MOCK_DIR/gh"

  export ORIG_PATH="$PATH"
  export PATH="$MOCK_DIR:$PATH"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

# ---------------------------------------------------------------------------
# No project scope — exits 0, no output, no mutation
# ---------------------------------------------------------------------------
@test "update-project-status: exits 0 when project scope is missing" {
  export GH_AUTH_SCOPES="'gist', 'repo'"  # no project scope
  run "$SCRIPT" owner repo 123
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Issue not in any project — exits 0, no output
# ---------------------------------------------------------------------------
@test "update-project-status: exits 0 when issue not in any project" {
  export GH_AUTH_SCOPES="'project', 'repo'"
  export GH_FIXTURE="$PROJECT_ROOT/tests/fixtures/update-project-status/no-projects.json"
  run "$SCRIPT" owner repo 123
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Item already "In Progress" — skipped, no mutation
# ---------------------------------------------------------------------------
@test "update-project-status: skips items already In Progress" {
  export GH_AUTH_SCOPES="'project', 'repo'"
  export GH_FIXTURE="$PROJECT_ROOT/tests/fixtures/update-project-status/already-in-progress.json"
  run "$SCRIPT" owner repo 123
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # No mutation should have fired
  ! grep -q "updateProjectV2ItemFieldValue" "$GH_CALLS"
}

# ---------------------------------------------------------------------------
# Item not In Progress — mutation fires, comment posted
# ---------------------------------------------------------------------------
@test "update-project-status: moves item to In Progress and comments" {
  export GH_AUTH_SCOPES="'project', 'repo'"
  export GH_FIXTURE="$PROJECT_ROOT/tests/fixtures/update-project-status/needs-update.json"
  run "$SCRIPT" owner repo 123
  [ "$status" -eq 0 ]
  # Should print summary line
  [[ "$output" == *'moved Status from "Todo" to "In Progress"'* ]]
  # Mutation and comment should have fired
  grep -q "updateProjectV2ItemFieldValue" "$GH_CALLS"
  grep -q "issue comment" "$GH_CALLS"
}

# ---------------------------------------------------------------------------
# Multiple projects — both updated
# ---------------------------------------------------------------------------
@test "update-project-status: updates multiple projects" {
  export GH_AUTH_SCOPES="'project', 'repo'"
  export GH_FIXTURE="$PROJECT_ROOT/tests/fixtures/update-project-status/multiple-projects.json"
  run "$SCRIPT" owner repo 123
  [ "$status" -eq 0 ]
  # Both projects should appear in output
  [[ "$output" == *"Roadmap"* ]]
  [[ "$output" == *"Sprint Board"* ]]
  # Two mutations
  mutation_count=$(grep -c "updateProjectV2ItemFieldValue" "$GH_CALLS" || true)
  [ "$mutation_count" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Project has no Status field — skipped silently
# ---------------------------------------------------------------------------
@test "update-project-status: skips project items with no Status field" {
  export GH_AUTH_SCOPES="'project', 'repo'"
  export GH_FIXTURE="$PROJECT_ROOT/tests/fixtures/update-project-status/no-status-field.json"
  run "$SCRIPT" owner repo 123
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! grep -q "updateProjectV2ItemFieldValue" "$GH_CALLS"
}

# ---------------------------------------------------------------------------
# Project has Status field but no "In Progress" option — skipped silently
# ---------------------------------------------------------------------------
@test "update-project-status: skips when no In Progress option exists" {
  export GH_AUTH_SCOPES="'project', 'repo'"
  export GH_FIXTURE="$PROJECT_ROOT/tests/fixtures/update-project-status/no-in-progress-option.json"
  run "$SCRIPT" owner repo 123
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! grep -q "updateProjectV2ItemFieldValue" "$GH_CALLS"
}

# ---------------------------------------------------------------------------
# GraphQL query fails — exits 0, no crash
# ---------------------------------------------------------------------------
@test "update-project-status: exits 0 when GraphQL query fails" {
  export GH_AUTH_SCOPES="'project', 'repo'"
  export GH_QUERY_FAIL="true"
  run "$SCRIPT" owner repo 123
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Mutation fails — continues gracefully
# ---------------------------------------------------------------------------
@test "update-project-status: continues when mutation fails" {
  export GH_AUTH_SCOPES="'project', 'repo'"
  export GH_FIXTURE="$PROJECT_ROOT/tests/fixtures/update-project-status/needs-update.json"
  export GH_MUTATION_FAIL="true"
  run "$SCRIPT" owner repo 123
  [ "$status" -eq 0 ]
  # Mutation was attempted
  grep -q "updateProjectV2ItemFieldValue" "$GH_CALLS"
  # Comment should NOT have fired (mutation failed before it)
  ! grep -q "issue comment" "$GH_CALLS"
}

# ---------------------------------------------------------------------------
# Comment posting fails — mutation still succeeds, exit 0
# ---------------------------------------------------------------------------
@test "update-project-status: succeeds even when comment posting fails" {
  export GH_AUTH_SCOPES="'project', 'repo'"
  export GH_FIXTURE="$PROJECT_ROOT/tests/fixtures/update-project-status/needs-update.json"
  export GH_COMMENT_FAIL="true"
  run "$SCRIPT" owner repo 123
  [ "$status" -eq 0 ]
  # Mutation should still have fired
  grep -q "updateProjectV2ItemFieldValue" "$GH_CALLS"
  [[ "$output" == *'moved Status'* ]]
}
