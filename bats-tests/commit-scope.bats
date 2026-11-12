#!/usr/bin/env bats
#
# Tests for skills/commit-msg/commit-scope.sh — the effective diff and the
# scope record of a /commit-msg scope. Each test builds a temporary git
# repository with one commit, then changes some of its files.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/commit-msg/commit-scope.sh"
SKILL="$PROJECT_ROOT/skills/commit-msg/SKILL.md"

setup() {
  TEST_TEMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  REPO="$TEST_TEMP_DIR/repo"
  mkdir -p "$REPO/d"
  cd "$REPO"
  git init -q
  git config user.email test@example.com
  git config user.name test
  printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n' > shared.txt
  echo a > d/a
  echo b > b
  git add .
  git commit -qm init
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# patch_of <file> <out> — write the working-tree diff of <file> to <out>, with
# one comment line above it, as a caller that records its work does.
patch_of() {
  { echo "# from the work of step 2"; git diff -- "$1"; } > "$2"
}

@test "commit-scope: a path gives its staged and its unstaged changes" {
  echo staged >> d/a
  git add d/a
  echo unstaged >> d/a
  run "$SCRIPT" --path d
  [ "$status" -eq 0 ]
  [[ "$output" == *"+staged"* ]] || false
  [[ "$output" == *"+unstaged"* ]] || false
}

@test "commit-scope: a change outside the scope does not reach the diff" {
  echo a2 >> d/a
  echo b2 >> b
  run "$SCRIPT" --path d
  [ "$status" -eq 0 ]
  [[ "$output" == *"d/a"* ]] || false
  [[ "$output" != *"b2"* ]] || false
}

@test "commit-scope: an untracked file under a path is a new file" {
  echo fresh > d/new
  run "$SCRIPT" --path d
  [ "$status" -eq 0 ]
  [[ "$output" == *"new file mode"* ]] || false
  [[ "$output" == *"+++ b/d/new"* ]] || false
}

@test "commit-scope: a patch prints from its first diff --git line" {
  sed -i.bak 's/^1$/one/' shared.txt && rm shared.txt.bak
  patch_of shared.txt "$TEST_TEMP_DIR/p.patch"
  run "$SCRIPT" --patch "$TEST_TEMP_DIR/p.patch"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "diff --git a/shared.txt b/shared.txt" ]] || false
  [[ "$output" != *"from the work of step 2"* ]] || false
}

@test "commit-scope: --record prints one line for each flag, in flag order" {
  echo a2 >> d/a
  echo b2 >> b
  sed -i.bak 's/^1$/one/' shared.txt && rm shared.txt.bak
  patch_of shared.txt "$TEST_TEMP_DIR/p.patch"
  run "$SCRIPT" --record --path b --patch "$TEST_TEMP_DIR/p.patch" --path d
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "# scope: path b" ]
  [ "${lines[1]}" = "# scope: patch $TEST_TEMP_DIR/p.patch" ]
  [ "${lines[2]}" = "# scope: path d" ]
}

@test "commit-scope: a relative path means the same file from a subdirectory" {
  echo a2 >> d/a
  cd d
  run "$SCRIPT" --path d
  [ "$status" -eq 0 ]
  [[ "$output" == *"+a2"* ]] || false
}

@test "commit-scope: a path with no change stops with J003" {
  run "$SCRIPT" --path b
  [ "$status" -eq 1 ]
  [[ "$output" == *"J003"* ]] || false
  [[ "$output" == *"'b'"* ]] || false
}

@test "commit-scope: a path outside the repository stops with J003" {
  run "$SCRIPT" --path /
  [ "$status" -eq 1 ]
  [[ "$output" == *"J003"* ]] || false
  [[ "$output" == *"outside the repository"* ]] || false
}

@test "commit-scope: a missing patch file stops with J004" {
  run "$SCRIPT" --patch "$TEST_TEMP_DIR/none.patch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"J004"* ]] || false
  [[ "$output" == *"does not exist"* ]] || false
}

@test "commit-scope: a patch file with no diff stops with J004" {
  echo "# only a comment" > "$TEST_TEMP_DIR/empty.patch"
  run "$SCRIPT" --patch "$TEST_TEMP_DIR/empty.patch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"J004"* ]] || false
  [[ "$output" == *"no 'diff --git' section"* ]] || false
}

@test "commit-scope: a file in a path and in a patch stops with J005" {
  sed -i.bak 's/^1$/one/' shared.txt && rm shared.txt.bak
  patch_of shared.txt "$TEST_TEMP_DIR/p.patch"
  run "$SCRIPT" --path shared.txt --patch "$TEST_TEMP_DIR/p.patch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"J005"* ]] || false
  [[ "$output" == *"'shared.txt'"* ]] || false
}

@test "commit-scope: a path and a patch of other files give both diffs" {
  echo a2 >> d/a
  sed -i.bak 's/^1$/one/' shared.txt && rm shared.txt.bak
  patch_of shared.txt "$TEST_TEMP_DIR/p.patch"
  run "$SCRIPT" --path d --patch "$TEST_TEMP_DIR/p.patch"
  [ "$status" -eq 0 ]
  [[ "$output" == *"+++ b/d/a"* ]] || false
  [[ "$output" == *"+++ b/shared.txt"* ]] || false
}

@test "commit-scope: a failed check prints no record" {
  run --separate-stderr "$SCRIPT" --record --path b
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "commit-scope: no flag stops with J001" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"J001"* ]] || false
}

@test "commit-scope: a flag with no value stops with J001" {
  run "$SCRIPT" --path
  [ "$status" -eq 1 ]
  [[ "$output" == *"J001"* ]] || false
}

@test "commit-scope: an unknown argument stops with J001" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"J001"* ]] || false
}

@test "commit-scope: --help prints the usage" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: commit-scope.sh"* ]] || false
}

@test "commit-scope: a cwd outside git stops with J002" {
  cd "$TEST_TEMP_DIR"
  run "$SCRIPT" --path d
  [ "$status" -eq 1 ]
  [[ "$output" == *"J002"* ]] || false
}

@test "commit-scope: a repository with no commit stops with J002" {
  mkdir "$TEST_TEMP_DIR/fresh"
  cd "$TEST_TEMP_DIR/fresh"
  git init -q
  run "$SCRIPT" --path d
  [ "$status" -eq 1 ]
  [[ "$output" == *"J002"* ]] || false
}

@test "commit-scope: the message keeps its scope lines out of the commit with --cleanup=strip" {
  echo a2 >> d/a
  { "$SCRIPT" --record --path d; printf '[feat] Add a line\n\nGenerated by /commit-msg\n'; } > "$TEST_TEMP_DIR/msg.txt"
  git add d
  git commit -q --cleanup=strip -F "$TEST_TEMP_DIR/msg.txt"
  run git log -1 --format=%B
  [[ "$output" != *"# scope:"* ]] || false
  [[ "$output" == *"[feat] Add a line"* ]] || false
}

@test "commit-msg skill: names the scope flags, the script, and the strip command" {
  grep -q -- "--path <path>" "$SKILL"
  grep -q -- "--patch <file>" "$SKILL"
  grep -q "commit-scope.sh" "$SKILL"
  grep -q -- "git commit --cleanup=strip -F" "$SKILL"
}

@test "commit-msg skill: a scope asks no staged question and writes no file on an error" {
  grep -q "ask no question" "$SKILL"
  grep -q "write no file" "$SKILL"
}
