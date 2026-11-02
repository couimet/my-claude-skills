#!/usr/bin/env bats
#
# Tests for scripts/stamp-skills.sh, issues/310 part: the script stamps the
# VERSION="..." line of install.sh with the value that it writes into each
# SKILL.md, in the same run. Each test runs in a fake repo with a fake
# skills tree, so the real files are never stamped.

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/stamp-skills.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  mkdir -p "$TEST_TEMP_DIR/skills/alpha"
  printf -- '---\nname: alpha\nversion: 2026.01.01@aaaaaaa\n---\n\n# Alpha\n' \
    > "$TEST_TEMP_DIR/skills/alpha/SKILL.md"
  printf '#!/bin/bash\n# header\nset -euo pipefail\n\nVERSION="2026.01.01@aaaaaaa"\necho "$VERSION"\n' \
    > "$TEST_TEMP_DIR/install.sh"
  chmod +x "$TEST_TEMP_DIR/install.sh"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

run_stamp() {
  run bash -c 'cd "$1" && shift && exec "$@"' _ "$TEST_TEMP_DIR" "$SCRIPT" "$@"
}

@test "stamp: install.sh gets the same version as the SKILL.md files" {
  run_stamp 2030.01.02@abc1234
  [ "$status" -eq 0 ]
  grep -qx 'version: 2030.01.02@abc1234' "$TEST_TEMP_DIR/skills/alpha/SKILL.md"
  grep -qx 'VERSION="2030.01.02@abc1234"' "$TEST_TEMP_DIR/install.sh"
  [[ "$output" == *"install.sh"*"2026.01.01@aaaaaaa → 2030.01.02@abc1234"* ]] || false
  [[ "$output" == *"Stamped 2 file(s), 0 skipped"* ]] || false
}

@test "stamp: only the VERSION line of install.sh changes, and it stays executable" {
  run_stamp 2030.01.02@abc1234
  [ "$status" -eq 0 ]
  [ -x "$TEST_TEMP_DIR/install.sh" ]
  run diff <(printf '#!/bin/bash\n# header\nset -euo pipefail\n\nVERSION="2030.01.02@abc1234"\necho "$VERSION"\n') "$TEST_TEMP_DIR/install.sh"
  [ "$status" -eq 0 ]
}

@test "stamp: install.sh already at the version is a no change" {
  run_stamp 2026.01.01@aaaaaaa
  [ "$status" -eq 0 ]
  [[ "$output" == *"install.sh"*"(no change)"* ]] || false
  [[ "$output" == *"Stamped 0 file(s), 2 skipped"* ]] || false
}

@test "stamp: --dry-run does not write install.sh" {
  run_stamp 2030.01.02@abc1234 --dry-run
  [ "$status" -eq 0 ]
  grep -qx 'VERSION="2026.01.01@aaaaaaa"' "$TEST_TEMP_DIR/install.sh"
  [[ "$output" == *"[dry run]"* ]] || false
}

@test "stamp: install.sh with no VERSION line is a warning, and nothing is inserted" {
  printf '#!/bin/bash\necho hi\n' > "$TEST_TEMP_DIR/install.sh"
  run_stamp 2030.01.02@abc1234
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: install.sh"*"no VERSION"* ]] || false
  [ "$(cat "$TEST_TEMP_DIR/install.sh")" = "$(printf '#!/bin/bash\necho hi')" ]
}

@test "stamp: a missing install.sh is a warning" {
  rm "$TEST_TEMP_DIR/install.sh"
  run_stamp 2030.01.02@abc1234
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: install.sh"*"file not found"* ]] || false
  [[ "$output" == *"1 warning(s)"* ]] || false
}

@test "stamp: the workflow checks and stages install.sh with skills/" {
  wf="$PROJECT_ROOT/.github/workflows/stamp-skills.yml"
  grep -q 'git diff --quiet skills/ install.sh' "$wf"
  grep -q 'git add skills/ install.sh' "$wf"
}
