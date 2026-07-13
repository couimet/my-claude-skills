#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/skills/create-github-issue/link-sub-issue.sh"

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
