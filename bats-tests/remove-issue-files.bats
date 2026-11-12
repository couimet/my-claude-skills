#!/usr/bin/env bats
#
# Tests for skills/issue-context/remove-issue-files.sh — deletes the issue
# files that /create-github-issue and /create-jira-issue write with /note,
# and refuses every other path, so a wrong argument never deletes a real note.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/remove-issue-files.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
}

teardown() {
  chmod -R u+w "${TEST_TEMP_DIR:?}" 2>/dev/null || true
  rm -rf "${TEST_TEMP_DIR:?}"
}

@test "remove-issue-files: --help exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: remove-issue-files.sh"* ]] || false
}

@test "remove-issue-files: I001 when given no path" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"I001"* ]] || false
}

@test "remove-issue-files: deletes a body file with the NNN counter" {
  f="$TEST_TEMP_DIR/20261019-101010-001-issue-body.md"
  touch "$f"
  run "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ ! -e "$f" ]
  [[ "$output" == *"removed $f"* ]] || false
}

@test "remove-issue-files: deletes a title file without the NNN counter" {
  f="$TEST_TEMP_DIR/20261019-101010-issue-title.txt"
  touch "$f"
  run "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ ! -e "$f" ]
}

@test "remove-issue-files: deletes a payload file" {
  f="$TEST_TEMP_DIR/20261019-101010-002-issue-payload.json"
  touch "$f"
  run "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ ! -e "$f" ]
}

@test "remove-issue-files: deletes a body file and a title file in one call" {
  body="$TEST_TEMP_DIR/20261019-101010-001-issue-body.md"
  title="$TEST_TEMP_DIR/20261019-101010-002-issue-title.md"
  touch "$body" "$title"
  run "$SCRIPT" "$body" "$title"
  [ "$status" -eq 0 ]
  [ ! -e "$body" ]
  [ ! -e "$title" ]
}

@test "remove-issue-files: I002 refuses a draft name and keeps the file" {
  f="$TEST_TEMP_DIR/20261019-101010-001-draft-issue-body.md"
  touch "$f"
  run "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ -f "$f" ]
  [[ "$output" == *"I002"* ]] || false
  [[ "$output" == *"$f"* ]] || false
}

@test "remove-issue-files: I002 refuses a description with a suffix" {
  f="$TEST_TEMP_DIR/20261019-101010-001-issue-payload-bug-a.md"
  touch "$f"
  run "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ -f "$f" ]
  [[ "$output" == *"I002"* ]] || false
}

@test "remove-issue-files: I002 refuses a name with no extension" {
  f="$TEST_TEMP_DIR/20261019-101010-001-issue-body"
  touch "$f"
  run "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ -f "$f" ]
}

@test "remove-issue-files: I002 refuses a name with no stamp" {
  f="$TEST_TEMP_DIR/issue-body.md"
  touch "$f"
  run "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ -f "$f" ]
}

@test "remove-issue-files: I002 refuses a directory with an issue-file name" {
  d="$TEST_TEMP_DIR/20261019-101010-001-issue-body.md"
  mkdir "$d"
  run "$SCRIPT" "$d"
  [ "$status" -eq 1 ]
  [ -d "$d" ]
  [[ "$output" == *"I002"* ]] || false
}

@test "remove-issue-files: I002 refuses a symlink and keeps its target" {
  target="$TEST_TEMP_DIR/real-note.md"
  link="$TEST_TEMP_DIR/20261019-101010-001-issue-body.md"
  touch "$target"
  ln -s "$target" "$link"
  run "$SCRIPT" "$link"
  [ "$status" -eq 1 ]
  [ -L "$link" ]
  [ -f "$target" ]
}

@test "remove-issue-files: I002 refuses a path that does not exist" {
  run "$SCRIPT" "$TEST_TEMP_DIR/20261019-101010-001-issue-body.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"I002"* ]] || false
}

@test "remove-issue-files: deletes the good path and keeps the refused one" {
  good="$TEST_TEMP_DIR/20261019-101010-001-issue-body.md"
  bad="$TEST_TEMP_DIR/20261019-101010-002-notes.md"
  touch "$good" "$bad"
  run "$SCRIPT" "$bad" "$good"
  [ "$status" -eq 1 ]
  [ ! -e "$good" ]
  [ -f "$bad" ]
}

@test "remove-issue-files: I003 when the delete fails" {
  [ "$(id -u)" -ne 0 ] || skip "root deletes from a read-only directory"
  dir="$TEST_TEMP_DIR/locked"
  mkdir "$dir"
  f="$dir/20261019-101010-001-issue-body.md"
  touch "$f"
  chmod a-w "$dir"
  run "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ -f "$f" ]
  [[ "$output" == *"I003"* ]] || false
}
