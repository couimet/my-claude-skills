#!/usr/bin/env bats
#
# Tests for skills/issue-context/skill-version.sh — prints a skill's version:
# field so the four footer-stamping skills stop reading their own front matter
# at runtime. Reading it in-model forced the front matter to stay in context
# and let a wrong stamp pass unnoticed, since nothing checked it.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/skill-version.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# _fake_install <root> — build a skills tree with a copy of the script in it,
# so resolution from the script's own location can be exercised without
# touching the real ~/.claude/skills.
_fake_install() {
  local root="$1"
  mkdir -p "$root/issue-context" "$root/demo-skill"
  cp "$SCRIPT" "$root/issue-context/skill-version.sh"
  printf -- '---\nname: demo-skill\nversion: 2026.01.02@abc1234\n---\n\n# Demo\n' \
    > "$root/demo-skill/SKILL.md"
}

@test "skill-version: --help exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: skill-version.sh"* ]]
}

@test "skill-version: V001 when given no argument" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"V001"* ]]
}

@test "skill-version: V001 when given two arguments" {
  run "$SCRIPT" a b
  [ "$status" -eq 1 ]
  [[ "$output" == *"V001"* ]]
}

@test "skill-version: V002 refuses a name that is not one path segment" {
  run "$SCRIPT" "../secrets"
  [ "$status" -eq 1 ]
  [[ "$output" == *"V002"* ]]
}

@test "skill-version: V003 when the skill has no SKILL.md" {
  run "$SCRIPT" "no-such-skill-anywhere"
  [ "$status" -eq 1 ]
  [[ "$output" == *"V003"* ]]
}

# The plugin-install case: the skills root is wherever the plugin unpacked to,
# not $HOME/.claude/skills. Resolving from the script's own location covers it.
@test "skill-version: resolves from its own location, not just \$HOME" {
  _fake_install "$TEST_TEMP_DIR/plugin-root"
  run env HOME="$TEST_TEMP_DIR/empty-home" \
    "$TEST_TEMP_DIR/plugin-root/issue-context/skill-version.sh" demo-skill
  [ "$status" -eq 0 ]
  [ "$output" = "2026.01.02@abc1234" ]
}

@test "skill-version: falls back to \$HOME/.claude/skills" {
  _fake_install "$TEST_TEMP_DIR/home/.claude/skills"
  mkdir -p "$TEST_TEMP_DIR/elsewhere/issue-context"
  cp "$SCRIPT" "$TEST_TEMP_DIR/elsewhere/issue-context/skill-version.sh"
  run env HOME="$TEST_TEMP_DIR/home" \
    "$TEST_TEMP_DIR/elsewhere/issue-context/skill-version.sh" demo-skill
  [ "$status" -eq 0 ]
  [ "$output" = "2026.01.02@abc1234" ]
}

# A `version:` line in the body is documentation. Only front matter is the stamp.
@test "skill-version: V004 ignores a version line outside the front matter" {
  local root="$TEST_TEMP_DIR/root"
  mkdir -p "$root/issue-context" "$root/bodyonly"
  cp "$SCRIPT" "$root/issue-context/skill-version.sh"
  printf -- '---\nname: bodyonly\n---\n\n# Body\n\nversion: 9999.12.31@deadbee\n' \
    > "$root/bodyonly/SKILL.md"
  run env HOME="$TEST_TEMP_DIR/empty-home" \
    "$root/issue-context/skill-version.sh" bodyonly
  [ "$status" -eq 1 ]
  [[ "$output" == *"V004"* ]]
}

@test "skill-version: prints the real version of a stamped skill in this repo" {
  run "$SCRIPT" commit-msg
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}.*@ ]]
}
