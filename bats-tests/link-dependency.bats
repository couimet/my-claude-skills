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
  [[ "$output" == *"E001"* ]] || false
  [[ "$output" == *"--subject-owner"* ]] || false
  [[ "$output" == *"--subject-repo"* ]] || false
  [[ "$output" == *"--subject-number"* ]] || false
  [[ "$output" == *"--target-owner"* ]] || false
  [[ "$output" == *"--target-repo"* ]] || false
  [[ "$output" == *"--target-number"* ]] || false
  [[ "$output" == *"--relationship"* ]] || false
}

@test "missing --relationship parameter prints error with E001" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5
  [ "$status" -eq 1 ]
  [[ "$output" == *"E001"* ]] || false
  [[ "$output" == *"--relationship"* ]] || false
}

@test "missing --subject-number parameter prints error with E001" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E001"* ]] || false
  [[ "$output" == *"--subject-number"* ]] || false
}

@test "missing --target-number parameter prints error with E001" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo \
                --relationship is-blocking
  [ "$status" -eq 1 ]
  [[ "$output" == *"E001"* ]] || false
  [[ "$output" == *"--target-number"* ]] || false
}

# --- Invalid numbers ---

@test "non-numeric --subject-number prints error with E102" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number abc \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E102"* ]] || false
  [[ "$output" == *"--subject-number"* ]] || false
}

@test "non-numeric --target-number prints error with E105" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number xyz \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E105"* ]] || false
  [[ "$output" == *"--target-number"* ]] || false
}

# --- Invalid relationship ---

@test "invalid relationship type prints error with E106" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship depends-on
  [ "$status" -eq 1 ]
  [[ "$output" == *"E106"* ]] || false
  [[ "$output" == *"--relationship"* ]] || false
  [[ "$output" == *"depends-on"* ]] || false
}

@test "empty relationship value treated as missing (E001)" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"E001"* ]] || false
  [[ "$output" == *"--relationship"* ]] || false
}

# --- Unknown parameters ---

@test "unknown parameter prints error with E002" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by --verbose
  [ "$status" -eq 1 ]
  [[ "$output" == *"E002"* ]] || false
  [[ "$output" == *"--verbose"* ]] || false
}

@test "positional parameter prints error with E002" {
  run "$SCRIPT" couimet
  [ "$status" -eq 1 ]
  [[ "$output" == *"E002"* ]] || false
}

# --- Parameter value missing ---

@test "--subject-owner without value prints error with E100" {
  run "$SCRIPT" --subject-owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"E100"* ]] || false
  [[ "$output" == *"--subject-owner"* ]] || false
}

@test "--subject-repo without value prints error with E101" {
  run "$SCRIPT" --subject-owner couimet --subject-repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"E101"* ]] || false
  [[ "$output" == *"--subject-repo"* ]] || false
}

@test "--target-owner without value prints error with E103" {
  run "$SCRIPT" --subject-owner couimet --target-owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"E103"* ]] || false
  [[ "$output" == *"--target-owner"* ]] || false
}

@test "--target-repo without value prints error with E104" {
  run "$SCRIPT" --subject-owner couimet --target-owner other --target-repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"E104"* ]] || false
  [[ "$output" == *"--target-repo"* ]] || false
}

@test "--relationship without value prints error with E106" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship
  [ "$status" -eq 1 ]
  [[ "$output" == *"E106"* ]] || false
  [[ "$output" == *"--relationship"* ]] || false
}

# --- Self-dependency ---

@test "same subject and target prints error with E107" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner couimet --target-repo my-repo --target-number 10 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E107"* ]] || false
  [[ "$output" == *"same issue"* ]] || false
}

# --- Runtime: subject node lookup failure (E200) ---

@test "subject node lookup failure prints error with E200" {
  export GH_FAIL_SUBJECT_QUERY=true
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E200"* ]] || false
  [[ "$output" == *"subject node ID lookup failed"* ]] || false
}

# --- Runtime: target node lookup failure (E201) ---

@test "target node lookup failure prints error with E201" {
  export GH_FAIL_TARGET_QUERY=true
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E201"* ]] || false
  [[ "$output" == *"target node ID lookup failed"* ]] || false
}

# --- Runtime: empty subject node ID (E202) ---

@test "empty subject node ID prints error with E202" {
  export GH_EMPTY_SUBJECT_ID=true
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E202"* ]] || false
  [[ "$output" == *"could not resolve node ID for subject issue"* ]] || false
}

# --- Runtime: empty target node ID (E203) ---

@test "empty target node ID prints error with E203" {
  export GH_EMPTY_TARGET_ID=true
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E203"* ]] || false
  [[ "$output" == *"could not resolve node ID for target issue"* ]] || false
}

# --- Runtime: mutation failure (E204) ---

@test "mutation failure (gh exit) prints error with E204" {
  export GH_FAIL_MUTATION=true
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E204"* ]] || false
  [[ "$output" == *"addBlockedBy mutation failed"* ]] || false
}

@test "mutation GraphQL errors prints error with E204" {
  export GH_GRAPHQL_ERRORS=true
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 1 ]
  [[ "$output" == *"E204"* ]] || false
  [[ "$output" == *"Dependency already exists"* ]] || false
}

# --- Success: blocked-by (same repo) ---

@test "blocked-by same-repo prints expected output" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner couimet --target-repo my-repo --target-number 5 \
                --relationship blocked-by
  [ "$status" -eq 0 ]
  [[ "$output" == "blocked #10 ← #5" ]] || false
}

# --- Success: is-blocking (cross-repo) ---

@test "is-blocking cross-repo prints expected output" {
  run "$SCRIPT" --subject-owner couimet --subject-repo my-repo --subject-number 10 \
                --target-owner other --target-repo other-repo --target-number 5 \
                --relationship is-blocking
  [ "$status" -eq 0 ]
  [[ "$output" == "blocking #10 → #5" ]] || false
}

# --- Help ---

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]] || false
  [[ "$output" == *"--subject-owner"* ]] || false
  [[ "$output" == *"--target-owner"* ]] || false
  [[ "$output" == *"--relationship"* ]] || false
}
