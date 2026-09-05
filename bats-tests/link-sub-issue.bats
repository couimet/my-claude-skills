#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/skills/create-github-issue/link-sub-issue.sh"

# --- Mock gh for success-path tests ---
#
# link-sub-issue makes two `gh api graphql` calls: call 1 is the node-ID
# lookup (parent in the parent repo, child in the child repo), call 2 is the
# addSubIssue mutation. GH_COUNTER distinguishes them, and every --input
# payload is snapshotted to call-<n>.json so tests can assert the request
# shape — in particular that the child resolves in its own repository rather
# than the parent's.

setup() {
  MOCK_DIR="$(mktemp -d)"
  export MOCK_DIR

  export GH_COUNTER="$MOCK_DIR/gh-counter"
  echo "0" > "$GH_COUNTER"

  cat > "$MOCK_DIR/gh" <<'MOCK_SCRIPT'
#!/usr/bin/env bash
case "$1" in
  api)
    COUNTER=$(cat "$GH_COUNTER")
    COUNTER=$((COUNTER + 1))
    echo "$COUNTER" > "$GH_COUNTER"

    # Locate the --input payload and snapshot it for assertions.
    input=""
    prev=""
    for arg in "$@"; do
      if [ "$prev" = "--input" ]; then
        input="$arg"
      fi
      prev="$arg"
    done
    if [ -n "$input" ]; then
      cp "$input" "$MOCK_DIR/call-$COUNTER.json"
    fi

    case "$COUNTER" in
      1)  # Node lookup
        if [ "${GH_FAIL_NODES:-}" = "true" ]; then
          echo "mock: node lookup failed" >&2
          exit 1
        fi
        if [ "${GH_EMPTY_CHILD_ID:-}" = "true" ]; then
          echo '{"data":{"repository":{"parent":{"id":"PARENT_NODE_ID"}},"childRepository":{"child":null}}}'
        else
          echo '{"data":{"repository":{"parent":{"id":"PARENT_NODE_ID"}},"childRepository":{"child":{"id":"CHILD_NODE_ID"}}}}'
        fi
        ;;
      2)  # Mutation
        if [ "${GH_FAIL_MUTATION:-}" = "true" ]; then
          echo "mock: mutation failed" >&2
          exit 1
        fi
        if [ "${GH_GRAPHQL_ERRORS:-}" = "true" ]; then
          echo '{"errors":[{"message":"mock: already a sub-issue"}]}'
        else
          echo '{"data":{"addSubIssue":{"issue":{"number":5},"subIssue":{"number":10}}}}'
        fi
        ;;
    esac
    ;;
esac
MOCK_SCRIPT
  chmod +x "$MOCK_DIR/gh"

  export PATH="$MOCK_DIR:$PATH"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

# --- Missing parameters ---

@test "missing all parameters prints error with E001" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"E001"* ]]
  [[ "$output" == *"--owner"* ]]
  [[ "$output" == *"--repo"* ]]
  [[ "$output" == *"--parent"* ]]
  [[ "$output" == *"--child"* ]]
}

@test "missing --parent parameter prints error with E001" {
  run "$SCRIPT" --owner couimet --repo my-repo --child 10
  [ "$status" -eq 1 ]
  [[ "$output" == *"E001"* ]]
  [[ "$output" == *"--parent"* ]]
}

@test "missing --child parameter prints error with E001" {
  run "$SCRIPT" --owner couimet --repo my-repo --parent 5
  [ "$status" -eq 1 ]
  [[ "$output" == *"E001"* ]]
  [[ "$output" == *"--child"* ]]
}

# --- Invalid numbers ---

@test "non-numeric --parent prints error with E102" {
  run "$SCRIPT" --owner couimet --repo my-repo --parent abc --child 10
  [ "$status" -eq 1 ]
  [[ "$output" == *"E102"* ]]
  [[ "$output" == *"--parent"* ]]
}

@test "non-numeric --child prints error with E103" {
  run "$SCRIPT" --owner couimet --repo my-repo --parent 5 --child xyz
  [ "$status" -eq 1 ]
  [[ "$output" == *"E103"* ]]
  [[ "$output" == *"--child"* ]]
}

# --- Unknown parameters ---

@test "unknown parameter prints error with E002" {
  run "$SCRIPT" --owner couimet --repo my-repo --parent 5 --child 10 --verbose
  [ "$status" -eq 1 ]
  [[ "$output" == *"E002"* ]]
  [[ "$output" == *"--verbose"* ]]
}

@test "positional parameter prints error with E002" {
  run "$SCRIPT" couimet
  [ "$status" -eq 1 ]
  [[ "$output" == *"E002"* ]]
}

# --- Parameter value missing ---

@test "--owner without value prints error with E100" {
  run "$SCRIPT" --owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"E100"* ]]
  [[ "$output" == *"--owner"* ]]
}

@test "--repo without value prints error with E101" {
  run "$SCRIPT" --owner couimet --repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"E101"* ]]
  [[ "$output" == *"--repo"* ]]
}

@test "--parent without value prints error with E102" {
  run "$SCRIPT" --owner couimet --repo my-repo --parent
  [ "$status" -eq 1 ]
  [[ "$output" == *"E102"* ]]
  [[ "$output" == *"--parent"* ]]
}

@test "--child without value prints error with E103" {
  run "$SCRIPT" --owner couimet --repo my-repo --parent 5 --child
  [ "$status" -eq 1 ]
  [[ "$output" == *"E103"* ]]
  [[ "$output" == *"--child"* ]]
}

# --- Help ---

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--owner"* ]]
  [[ "$output" == *"--parent"* ]]
  [[ "$output" == *"--child"* ]]
}

# --- Success paths ---

@test "child missing value error prints E104 for --child-owner" {
  run "$SCRIPT" --owner couimet --repo my-repo --parent 5 --child 10 --child-owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"E104"* ]]
  [[ "$output" == *"--child-owner"* ]]
}

@test "child missing value error prints E105 for --child-repo" {
  run "$SCRIPT" --owner couimet --repo my-repo --parent 5 --child 10 --child-repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"E105"* ]]
  [[ "$output" == *"--child-repo"* ]]
}

@test "cross-repository child is resolved in the child's own repo" {
  run "$SCRIPT" --owner couimet --repo parent-repo --parent 5 \
                --child-owner other-org --child-repo child-repo --child 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"linked #10 → #5"* ]]

  # The node-lookup payload must ask for the parent in the parent repo and
  # the child in the child repo — not resolve both against the parent's.
  local owner repo child_owner child_repo
  owner="$(jq -r '.variables.owner // empty' "$MOCK_DIR/call-1.json")"
  repo="$(jq -r '.variables.repo // empty' "$MOCK_DIR/call-1.json")"
  child_owner="$(jq -r '.variables.childOwner // empty' "$MOCK_DIR/call-1.json")"
  child_repo="$(jq -r '.variables.childRepo // empty' "$MOCK_DIR/call-1.json")"
  [ "$owner" = "couimet" ]
  [ "$repo" = "parent-repo" ]
  [ "$child_owner" = "other-org" ]
  [ "$child_repo" = "child-repo" ]
}

@test "child repo defaults to the parent repo when child flags are omitted" {
  run "$SCRIPT" --owner couimet --repo my-repo --parent 5 --child 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"linked #10 → #5"* ]]

  local child_owner child_repo
  child_owner="$(jq -r '.variables.childOwner // empty' "$MOCK_DIR/call-1.json")"
  child_repo="$(jq -r '.variables.childRepo // empty' "$MOCK_DIR/call-1.json")"
  [ "$child_owner" = "couimet" ]
  [ "$child_repo" = "my-repo" ]
}

@test "missing child node id reports E201" {
  export GH_EMPTY_CHILD_ID=true
  run "$SCRIPT" --owner couimet --repo my-repo --parent 5 --child 10
  [ "$status" -eq 1 ]
  [[ "$output" == *"E201"* ]]
  [[ "$output" == *"child issue #10"* ]]
}

@test "GraphQL mutation error reports E202" {
  export GH_GRAPHQL_ERRORS=true
  run "$SCRIPT" --owner couimet --repo my-repo --parent 5 --child 10
  [ "$status" -eq 1 ]
  [[ "$output" == *"E202"* ]]
  [[ "$output" == *"already a sub-issue"* ]]
}
