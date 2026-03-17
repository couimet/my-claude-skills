#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/skills/auto-number/auto-number.sh"

# --- Prefix mode: empty directory ---

@test "prefix mode: empty directory returns 0001" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode prefix
  [ "$status" -eq 0 ]
  [ "$output" = "0001" ]
}

# --- Suffix mode: empty directory ---

@test "suffix mode: empty directory returns 0001" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode suffix
  [ "$status" -eq 0 ]
  [ "$output" = "0001" ]
}

# --- Default mode is prefix ---

@test "default mode: omitting --mode defaults to prefix" {
  touch "$TEST_TEMP_DIR/foo-0005.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "0001" ]
}

# --- Prefix mode: finds max and increments ---

@test "prefix mode: finds max from existing files and increments" {
  touch "$TEST_TEMP_DIR/0001-foo.txt"
  touch "$TEST_TEMP_DIR/0003-bar.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode prefix
  [ "$status" -eq 0 ]
  [ "$output" = "0004" ]
}

# --- Prefix mode: handles gaps correctly ---

@test "prefix mode: handles gaps correctly (returns max+1, not next sequential)" {
  touch "$TEST_TEMP_DIR/0001-first.txt"
  touch "$TEST_TEMP_DIR/0005-fifth.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode prefix
  [ "$status" -eq 0 ]
  [ "$output" = "0006" ]
}

# --- Suffix mode: finds max and increments ---

@test "suffix mode: finds max from existing files and increments" {
  touch "$TEST_TEMP_DIR/foo-0002.txt"
  touch "$TEST_TEMP_DIR/bar-0001.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode suffix
  [ "$status" -eq 0 ]
  [ "$output" = "0003" ]
}

# --- Ignores non-matching files ---

@test "prefix mode: ignores files without leading digits" {
  touch "$TEST_TEMP_DIR/readme.txt"
  touch "$TEST_TEMP_DIR/notes.md"
  touch "$TEST_TEMP_DIR/0003-real.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode prefix
  [ "$status" -eq 0 ]
  [ "$output" = "0004" ]
}

@test "suffix mode: ignores files without trailing digits" {
  touch "$TEST_TEMP_DIR/readme.txt"
  touch "$TEST_TEMP_DIR/notes.md"
  touch "$TEST_TEMP_DIR/real-0003.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode suffix
  [ "$status" -eq 0 ]
  [ "$output" = "0004" ]
}

# --- No glob: scans all extensions ---

@test "prefix mode: without --glob, scans all extensions" {
  touch "$TEST_TEMP_DIR/0005-data.json"
  touch "$TEST_TEMP_DIR/0002-notes.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode prefix
  [ "$status" -eq 0 ]
  [ "$output" = "0006" ]
}

@test "suffix mode: without --glob, scans all extensions" {
  touch "$TEST_TEMP_DIR/data-0005.json"
  touch "$TEST_TEMP_DIR/notes-0002.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode suffix
  [ "$status" -eq 0 ]
  [ "$output" = "0006" ]
}

# --- Custom glob pattern ---

@test "prefix mode: --glob filters to only matching files" {
  touch "$TEST_TEMP_DIR/0005-data.json"
  touch "$TEST_TEMP_DIR/0002-notes.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode prefix --glob "*.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "0003" ]
}

@test "suffix mode: --glob filters to only matching files" {
  touch "$TEST_TEMP_DIR/data-0005.json"
  touch "$TEST_TEMP_DIR/notes-0002.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode suffix --glob "*.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "0003" ]
}

# --- Width: default ---

@test "width: default (no --width) produces 4-digit output" {
  run "$SCRIPT" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "0001" ]
}

# --- Width: custom ---

@test "width: --width 6 produces 6-digit output" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --width 6
  [ "$status" -eq 0 ]
  [ "$output" = "000001" ]
}

@test "width: --width 2 produces 2-digit output" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --width 2
  [ "$status" -eq 0 ]
  [ "$output" = "01" ]
}

# --- Width: safety override ---

@test "width: safety override when next value needs more digits than requested" {
  touch "$TEST_TEMP_DIR/0999-foo.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode prefix --width 3
  [ "$status" -eq 0 ]
  [ "$output" = "1000" ]
}

# --- Width: validation errors ---

@test "width: --width 0 exits with E101" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --width 0
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E101 error: "* ]]
}

@test "width: --width -1 exits with E101" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --width -1
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E101 error: "* ]]
}

@test "width: --width 11 exits with E101 (exceeds cap)" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --width 11
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E101 error: "* ]]
}

@test "width: --width abc exits with E101 (non-integer)" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --width abc
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E101 error: "* ]]
}

# --- Help ---

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: auto-number.sh"* ]]
}

# --- Error handling ---

@test "missing directory argument exits with E001" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E001 error: "* ]]
}

@test "directory does not exist exits with E102" {
  run "$SCRIPT" "$TEST_TEMP_DIR/nonexistent"
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E102 error: "* ]]
}

# --- --mkdir flag ---

@test "--mkdir: creates nonexistent directory and returns 0001" {
  run "$SCRIPT" "$TEST_TEMP_DIR/newdir" --mkdir
  [ "$status" -eq 0 ]
  [ "$output" = "0001" ]
  [ -d "$TEST_TEMP_DIR/newdir" ]
}

@test "--mkdir: creates nested nonexistent path and returns 0001" {
  run "$SCRIPT" "$TEST_TEMP_DIR/a/b/c" --mkdir
  [ "$status" -eq 0 ]
  [ "$output" = "0001" ]
  [ -d "$TEST_TEMP_DIR/a/b/c" ]
}

@test "--mkdir: works normally with existing populated directory" {
  touch "$TEST_TEMP_DIR/0003-foo.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" --mkdir
  [ "$status" -eq 0 ]
  [ "$output" = "0004" ]
}

@test "path is not a directory exits with E103" {
  touch "$TEST_TEMP_DIR/a-file.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR/a-file.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E103 error: "* ]]
}

@test "directory not readable exits with E104" {
  [ "$EUID" -ne 0 ] || skip "chmod 000 is bypassed for root"
  mkdir "$TEST_TEMP_DIR/locked"
  chmod 000 "$TEST_TEMP_DIR/locked"
  run "$SCRIPT" "$TEST_TEMP_DIR/locked"
  chmod 755 "$TEST_TEMP_DIR/locked"
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E104 error: "* ]]
}

@test "invalid --mode argument exits with E100" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode badmode
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E100 error: "* ]]
}

@test "unknown flag exits with E002" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E002 error: "* ]]
}

@test "positional 'prefix' is tolerated as --mode prefix" {
  touch "$TEST_TEMP_DIR/0003-foo.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" prefix
  [ "$status" -eq 0 ]
  [ "$output" = "0004" ]
}

@test "positional 'suffix' is tolerated as --mode suffix" {
  touch "$TEST_TEMP_DIR/foo-0003.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR" suffix
  [ "$status" -eq 0 ]
  [ "$output" = "0004" ]
}

@test "duplicate positional mode 'prefix suffix' exits with E002" {
  run "$SCRIPT" "$TEST_TEMP_DIR" prefix suffix
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E002 error: "* ]]
  [[ "$output" == *"mode already set"* ]]
}

@test "positional mode after --mode flag exits with E002" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode prefix suffix
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E002 error: "* ]]
  [[ "$output" == *"mode already set"* ]]
}

# --- Flag without value (last argument) ---

@test "--mode as last arg without value exits with E100" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --mode
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E100 error: "* ]]
}

@test "--glob as last arg without value exits with E105" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --glob
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E105 error: "* ]]
}

@test "--width as last arg without value exits with E101" {
  run "$SCRIPT" "$TEST_TEMP_DIR" --width
  [ "$status" -eq 1 ]
  [[ "$output" == "auto-number E101 error: "* ]]
}
