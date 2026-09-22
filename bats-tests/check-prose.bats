#!/usr/bin/env bats
#
# Tests for skills/prose-style/check-prose.sh — reports the mechanical prose
# violations in a generated file by line number. The point is token cost: a
# caller that re-reads its own output pulls the whole file back into context,
# where this prints a handful of lines. A script's source never enters context,
# only its stdout, which is the trade extract-answers.sh already makes.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/prose-style/check-prose.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  FILE="$TEST_TEMP_DIR/doc.txt"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# =============================================================
# Usage
# =============================================================

@test "check-prose: --help exits 0 and names the usage" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: check-prose.sh"* ]]
}

@test "check-prose: P000 when given no argument" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "check-prose: P000 when the file does not exist" {
  run "$SCRIPT" "$TEST_TEMP_DIR/missing.txt"
  [ "$status" -eq 2 ]
}

# =============================================================
# A clean file costs nothing
# =============================================================

@test "check-prose: a clean file prints nothing and exits 0" {
  printf '# Title\n\nOne continuous paragraph that does not wrap at any column.\n\nA second one, naming src/parser.ts#L42 bare and https://github.com/owner/repo/issues/12 in full.\n' > "$FILE"
  run "$SCRIPT" "$FILE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================
# Each mechanical rule
# =============================================================

@test "check-prose: P001 flags a mid-paragraph line break" {
  printf '# Title\n\nThis paragraph was wrapped by an editor\nand continues on a second line.\n' > "$FILE"
  run "$SCRIPT" "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P001"* ]]
}

@test "check-prose: P002 flags a backtick-wrapped code reference" {
  printf '# Title\n\nSee `src/parser.ts#L42` for the detail.\n' > "$FILE"
  run "$SCRIPT" "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P002"* ]]
}

@test "check-prose: P003 flags a plain-text line reference" {
  printf '# Title\n\nThat regressed in lines 26-37 of the parser.\n' > "$FILE"
  run "$SCRIPT" "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P003"* ]]
}

@test "check-prose: P004 flags a short-form GitHub reference" {
  printf '# Title\n\nFixed by PR #42 last week.\n' > "$FILE"
  run "$SCRIPT" "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P004"* ]]
}

@test "check-prose: P005 flags a relative .claude-work path" {
  printf '# Title\n\nThe file landed in .claude-work/notes/thing.txt for review.\n' > "$FILE"
  run "$SCRIPT" "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P005"* ]]
}

# =============================================================
# Exemptions. A checker that cried wolf on its own documentation would be
# turned off, and these skills document the very forms it flags.
# =============================================================

@test "check-prose: a fenced block is exempt from every rule" {
  printf '# Title\n\n```text\nlines 26-37 and PR #42 and .claude-work/x.txt\nand a wrapped\nline too\n```\n' > "$FILE"
  run "$SCRIPT" "$FILE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check-prose: a table row is exempt" {
  printf '# Title\n\n| Ref | Bad form |\n| --- | -------- |\n| a   | lines 26-37 |\n' > "$FILE"
  run "$SCRIPT" "$FILE"
  [ "$status" -eq 0 ]
}

@test "check-prose: a list item is exempt from the wrap rule" {
  printf '# Title\n\n- one item\n- another item\n' > "$FILE"
  run "$SCRIPT" "$FILE"
  [ "$status" -eq 0 ]
}

@test "check-prose: an absolute .claude-work path is not a finding" {
  printf '# Title\n\nCreated: /Users/x/project/.claude-work/notes/thing.txt\n' > "$FILE"
  run "$SCRIPT" "$FILE"
  [ "$status" -eq 0 ]
}

@test "check-prose: two sentences on separate lines are not a wrap" {
  printf '# Title\n\nThe first sentence ends here.\nThe second starts here.\n' > "$FILE"
  run "$SCRIPT" "$FILE"
  [ "$status" -eq 0 ]
}

@test "check-prose: reports every finding, not just the first" {
  printf '# Title\n\nSee `src/parser.ts#L42` here.\n\nFixed by PR #42 last week.\n' > "$FILE"
  run "$SCRIPT" "$FILE"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
}
