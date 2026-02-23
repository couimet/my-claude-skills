#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/skills/auto-number/auto-number.sh"

# --- Prefix mode: empty directory ---

@test "prefix mode: empty directory returns 0001" {
  run "$SCRIPT" "$TEST_TEMP_DIR" prefix
  [ "$status" -eq 0 ]
  [ "$output" = "0001" ]
}

# --- Suffix mode: empty directory ---

@test "suffix mode: empty directory returns 0001" {
  run "$SCRIPT" "$TEST_TEMP_DIR" suffix
  [ "$status" -eq 0 ]
  [ "$output" = "0001" ]
}

# --- Prefix mode: finds max and increments ---

@test "prefix mode: finds max from existing files and increments" {
  touch "$TEST_TEMP_DIR/0001-foo.txt"
  touch "$TEST_TEMP_DIR/0003-bar.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" prefix
  [ "$status" -eq 0 ]
  [ "$output" = "0004" ]
}

# --- Prefix mode: handles gaps correctly ---

@test "prefix mode: handles gaps correctly (returns max+1, not next sequential)" {
  touch "$TEST_TEMP_DIR/0001-first.txt"
  touch "$TEST_TEMP_DIR/0005-fifth.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" prefix
  [ "$status" -eq 0 ]
  [ "$output" = "0006" ]
}

# --- Suffix mode: finds max and increments ---

@test "suffix mode: finds max from existing files and increments" {
  touch "$TEST_TEMP_DIR/foo-0002.txt"
  touch "$TEST_TEMP_DIR/bar-0001.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" suffix
  [ "$status" -eq 0 ]
  [ "$output" = "0003" ]
}

# --- Ignores non-matching files ---

@test "prefix mode: ignores files without leading digits" {
  touch "$TEST_TEMP_DIR/readme.txt"
  touch "$TEST_TEMP_DIR/notes.md"
  touch "$TEST_TEMP_DIR/0003-real.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" prefix
  [ "$status" -eq 0 ]
  [ "$output" = "0004" ]
}

@test "suffix mode: ignores files without trailing digits" {
  touch "$TEST_TEMP_DIR/readme.txt"
  touch "$TEST_TEMP_DIR/notes.md"
  touch "$TEST_TEMP_DIR/real-0003.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" suffix
  [ "$status" -eq 0 ]
  [ "$output" = "0004" ]
}

# --- Custom glob_pattern ---

@test "prefix mode: glob_pattern filters to only matching files" {
  touch "$TEST_TEMP_DIR/0005-data.json"
  touch "$TEST_TEMP_DIR/0002-notes.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" prefix "*.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "0003" ]
}

@test "suffix mode: glob_pattern filters to only matching files" {
  touch "$TEST_TEMP_DIR/data-0005.json"
  touch "$TEST_TEMP_DIR/notes-0002.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" suffix "*.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "0003" ]
}

# --- Error handling ---

@test "missing directory argument exits with error" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == "auto-number error: "* ]]
}

@test "invalid mode argument exits with error" {
  run "$SCRIPT" "$TEST_TEMP_DIR" "badmode"
  [ "$status" -ne 0 ]
  [[ "$output" == "auto-number error: "* ]]
}
