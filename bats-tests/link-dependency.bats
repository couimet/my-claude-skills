#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/skills/create-github-issue/link-dependency.sh"

# --- Mock gh for runtime error code tests ---

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

    case "$COUNTER" in
      1)  # Subject query
        if [ "${GH_FAIL_SUBJECT_QUERY:-}" = "true" ]; then
          echo "mock: subject query failed" >&2
          exit 1
        fi
        if [ "${GH_EMPTY_SUBJECT_ID:-}" = "true" ]; then
          echo '{"data":{"repository":{"issue":null}}}'
        else
          echo '{"data":{"repository":{"issue":{"id":"SUBJECT_NODE_ID"}}}}'
        fi
        ;;
      2)  # Target query
        if [ "${GH_FAIL_TARGET_QUERY:-}" = "true" ]; then
          echo "mock: target query failed" >&2
          exit 1
        fi
        if [ "${GH_EMPTY_TARGET_ID:-}" = "true" ]; then
          echo '{"data":{"repository":{"issue":null}}}'
        else
          echo '{"data":{"repository":{"issue":{"id":"TARGET_NODE_ID"}}}}'
        fi
        ;;
      3)  # Mutation
        if [ "${GH_FAIL_MUTATION:-}" = "true" ]; then
          echo "mock: mutation failed" >&2
          exit 1
        fi
        if [ "${GH_GRAPHQL_ERRORS:-}" = "true" ]; then
          echo '{"errors":[{"message":"Dependency already exists"}]}'
        else
          echo '{"data":{"addBlockedBy":{"issue":{"number":10},"blockingIssue":{"number":5}}}}'
        fi
        ;;
    esac
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

# --- Missing parameters ---

@test "missing all parameters prints error with E001" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"E001"* ]]
  [[ "$output" == *"--subject-owner"* ]]
  [[ "$output" == *"--subject-repo"* ]]
  [[ "$output" == *"--subject-number"* ]]
  [[ "$output" == *"--target-owner"* ]]
  [[ "$output" == *"--target-repo"* ]]
  [[ "$output" == *"--target-number"* ]]
  [[ "$output" == *"--relationship"* ]]
}

@test "missing --relationship parameter prints error with E001" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5
  [ "$status" -eq 1 ]
  [[ "$output" == *"E001"* ]]
  [[ "$output" == *"--relationship"* ]]
}

@test "missing --subject-number parameter prints error with E001" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E001"* ]]
  [[ "$output" == *"--subject-number"* ]]
}

@test "missing --target-number parameter prints error with E001" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo \
                --relationship is-blocking
  [ "$status" -eq 1 ]
  [[ "$output" == *"E001"* ]]
  [[ "$output" == *"--target-number"* ]]
}

# --- Invalid numbers ---

@test "non-numeric --subject-number prints error with E102" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number abc \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E102"* ]]
  [[ "$output" == *"--subject-number"* ]]
}

@test "non-numeric --target-number prints error with E105" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number xyz \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E105"* ]]
  [[ "$output" == *"--target-number"* ]]
}

# --- Invalid relationship ---

@test "invalid relationship type prints error with E106" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship depends-on
  [ "$status" -eq 1 ]
  [[ "$output" == *"E106"* ]]
  [[ "$output" == *"--relationship"* ]]
  [[ "$output" == *"depends-on"* ]]
}

@test "empty relationship value treated as missing (E001)" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"E001"* ]]
  [[ "$output" == *"--relationship"* ]]
}

# --- Unknown parameters ---

@test "unknown parameter prints error with E002" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by --verbose
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

@test "--subject-owner without value prints error with E100" {
  run "$SCRIPT" --subject-owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"E100"* ]]
  [[ "$output" == *"--subject-owner"* ]]
}

@test "--subject-repo without value prints error with E101" {
  run "$SCRIPT" --subject-owner couimet --subject-repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"E101"* ]]
  [[ "$output" == *"--subject-repo"* ]]
}

@test "--target-owner without value prints error with E103" {
  run "$SCRIPT" --subject-owner couimet --target-owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"E103"* ]]
  [[ "$output" == *"--target-owner"* ]]
}

@test "--target-repo without value prints error with E104" {
  run "$SCRIPT" --subject-owner couimet --target-owner other --target-repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"E104"* ]]
  [[ "$output" == *"--target-repo"* ]]
}

@test "--relationship without value prints error with E106" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship
  [ "$status" -eq 1 ]
  [[ "$output" == *"E106"* ]]
  [[ "$output" == *"--relationship"* ]]
}

# --- Self-dependency ---

@test "same subject and target prints error with E107" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner couimet --target-repo my-repo --target-number 10 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E107"* ]]
  [[ "$output" == *"same issue"* ]]
}

# --- Runtime: subject node lookup failure (E200) ---

@test "subject node lookup failure prints error with E200" {
  export GH_FAIL_SUBJECT_QUERY=true
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E200"* ]]
  [[ "$output" == *"subject node ID lookup failed"* ]]
}

# --- Runtime: target node lookup failure (E201) ---

@test "target node lookup failure prints error with E201" {
  export GH_FAIL_TARGET_QUERY=true
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E201"* ]]
  [[ "$output" == *"target node ID lookup failed"* ]]
}

# --- Runtime: empty subject node ID (E202) ---

@test "empty subject node ID prints error with E202" {
  export GH_EMPTY_SUBJECT_ID=true
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E202"* ]]
  [[ "$output" == *"could not resolve node ID for subject issue"* ]]
}

# --- Runtime: empty target node ID (E203) ---

@test "empty target node ID prints error with E203" {
  export GH_EMPTY_TARGET_ID=true
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E203"* ]]
  [[ "$output" == *"could not resolve node ID for target issue"* ]]
}

# --- Runtime: mutation failure (E204) ---

@test "mutation failure (gh exit) prints error with E204" {
  export GH_FAIL_MUTATION=true
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E204"* ]]
  [[ "$output" == *"addBlockedBy mutation failed"* ]]
}

@test "mutation GraphQL errors prints error with E204" {
  export GH_GRAPHQL_ERRORS=true
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E204"* ]]
  [[ "$output" == *"Dependency already exists"* ]]
}

# --- Success: blocked-by (same repo) ---

@test "blocked-by same-repo prints expected output" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner couimet --target-repo my-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 0 ]
  [[ "$output" == "blocked #10 ← #5" ]]
}

# --- Success: is-blocking (cross-repo) ---

@test "is-blocking cross-repo prints expected output" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship is-blocking
  [ "$status" -eq 0 ]
  [[ "$output" == "blocking #10 → #5" ]]
}

# --- Help ---

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--subject-owner"* ]]
  [[ "$output" == *"--target-owner"* ]]
  [[ "$output" == *"--relationship"* ]]
}
