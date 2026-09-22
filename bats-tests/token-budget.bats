#!/usr/bin/env bats
#
# Tests for scripts/token-budget.sh and scripts/check-script-headers.sh — the
# size budget from ADR 005 and the script-header convention. The budget only
# means something if the tiers, the allowlist matching, and the exit codes all
# behave, so these hold the measurement honest.

bats_require_minimum_version 1.7.0

load test_helper

BUDGET="$PROJECT_ROOT/scripts/token-budget.sh"
HEADERS="$PROJECT_ROOT/scripts/check-script-headers.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  SKILLS="$TEST_TEMP_DIR/skills"
  mkdir -p "$SKILLS"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# _skill <name> <bytes> [frontmatter-extra]
_skill() {
  local name="$1" bytes="$2" extra="${3:-}"
  mkdir -p "$SKILLS/$name"
  {
    printf -- '---\nname: %s\ndescription: A test skill.\n' "$name"
    [ -n "$extra" ] && printf '%s\n' "$extra"
    printf -- '---\n\n# %s\n\n' "$name"
    head -c "$bytes" /dev/zero | tr '\0' 'x'
    printf '\n'
  } > "$SKILLS/$name/SKILL.md"
}

# =============================================================
# Tiers
# =============================================================

@test "token-budget: an ordinary skill under 8000 passes" {
  _skill small 100
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
}

@test "token-budget: an ordinary skill over 8000 fails --check" {
  _skill big 9000
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"big"* ]]
}

@test "token-budget: a foundation skill is capped at 4000, not 8000" {
  _skill found 5000 "user-invocable: false"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"found"* ]]
}

@test "token-budget: a composite skill is capped at 12000, not 8000" {
  _skill comp 9000 "skill-kind: composite"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
}

@test "token-budget: a composite skill over 12000 still fails" {
  _skill comp 13000 "skill-kind: composite"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 1 ]
}

# =============================================================
# The allowlist is a backlog, so an entry must be explicit
# =============================================================

@test "token-budget: an allowlisted skill passes --check" {
  _skill big 9000
  printf 'big\n' > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
}

@test "token-budget: the allowlist ignores comments and blank lines" {
  _skill big 9000
  printf '# a comment\n\nbig\n' > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
}

@test "token-budget: an allowlist entry for another skill does not cover this one" {
  _skill big 9000
  printf 'someone-else\n' > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 1 ]
}

# A partial name must not match. `grep -qxF` rather than `grep -q`.
@test "token-budget: an allowlist entry matches the whole name only" {
  _skill big 9000
  printf 'bigger\n' > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 1 ]
}

# =============================================================
# Report mode
# =============================================================

@test "token-budget: report mode exits 0 even with a skill over cap" {
  _skill big 9000
  run "$BUDGET" --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OVER"* ]]
}

@test "token-budget: report names both the body total and the session floor" {
  _skill small 100
  run "$BUDGET" --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bodies:"* ]]
  [[ "$output" == *"Descriptions:"* ]]
}

@test "token-budget: B001 on an unknown argument" {
  run "$BUDGET" --nope
  [ "$status" -eq 2 ]
}

@test "token-budget: B002 when the skills dir does not exist" {
  run "$BUDGET" --skills-dir "$TEST_TEMP_DIR/nope"
  [ "$status" -eq 2 ]
}

# =============================================================
# The real tree must satisfy its own gate
# =============================================================

@test "token-budget: the repo passes --check" {
  run "$BUDGET" --check
  [ "$status" -eq 0 ]
}

# =============================================================
# Script headers
# =============================================================

@test "check-script-headers: the repo passes" {
  run "$HEADERS"
  [ "$status" -eq 0 ]
}

@test "check-script-headers: a script with no header fails" {
  mkdir -p "$TEST_TEMP_DIR/s"
  printf '#!/usr/bin/env bash\necho hi\n' > "$TEST_TEMP_DIR/s/bare.sh"
  run "$HEADERS" "$TEST_TEMP_DIR/s"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bare.sh"* ]]
}

@test "check-script-headers: a script with a header passes" {
  mkdir -p "$TEST_TEMP_DIR/s"
  printf '#!/usr/bin/env bash\n#\n# ok.sh — does a thing.\n#\n# Usage: ok.sh\n#\n# Exit codes: 0\n\necho hi\n' > "$TEST_TEMP_DIR/s/ok.sh"
  run "$HEADERS" "$TEST_TEMP_DIR/s"
  [ "$status" -eq 0 ]
}
