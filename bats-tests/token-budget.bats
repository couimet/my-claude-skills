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
  [[ "$output" == *"big"* ]] || false
}

@test "token-budget: a foundation skill is capped at 4000, not 8000" {
  _skill found 5000 "user-invocable: false"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"found"* ]] || false
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
  printf 'big 9100\n' > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
}

@test "token-budget: the allowlist ignores comments and blank lines" {
  _skill big 9000
  printf '# a comment\n\nbig 9100\n' > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
}

@test "token-budget: an allowlist entry for another skill does not cover this one" {
  _skill big 9000
  printf 'someone-else 9100\n' > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 1 ]
}

# A partial name must not match. `grep -qxF` rather than `grep -q`.
@test "token-budget: an allowlist entry matches the whole name only" {
  _skill big 9000
  printf 'bigger 9100\n' > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 1 ]
}

# =============================================================
# The recorded size is a ratchet: a listed skill may shrink, not grow
# =============================================================

# _size <name> — print the byte size of a test skill, as the script counts it.
_size() {
  wc -c < "$SKILLS/$1/SKILL.md" | tr -d ' '
}

@test "token-budget: a listed skill at its recorded size passes --check" {
  _skill big 9000
  printf 'big %s\n' "$(_size big)" > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
}

@test "token-budget: a listed skill under its recorded size passes --check" {
  _skill big 9000
  printf 'big %s\n' "$(($(_size big) + 500))" > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
}

@test "token-budget: a listed skill one byte past its recorded size fails --check" {
  _skill big 9000
  local recorded=$(($(_size big) - 1))
  printf 'big %s\n' "$recorded" > "$SKILLS/.budget-allowlist"
  run --separate-stderr "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"big is $(_size big) bytes, past the $recorded bytes"* ]] || false
}

@test "token-budget: a listed skill with no recorded size fails --check and names the line to write" {
  _skill big 9000
  printf 'big\n' > "$SKILLS/.budget-allowlist"
  run --separate-stderr "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no recorded size; write its line as 'big $(_size big)'"* ]] || false
}

@test "token-budget: a recorded size that is not a number fails --check" {
  _skill big 9000
  printf 'big lots\n' > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 1 ]
}

@test "token-budget: a listed skill under its cap passes whatever its line records" {
  _skill small 100
  printf 'small 10\n' > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --check --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
}

@test "token-budget: report mode marks a listed skill that grew as GREW" {
  _skill big 9000
  printf 'big 9001\n' > "$SKILLS/.budget-allowlist"
  run "$BUDGET" --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GREW"* ]] || false
}

# =============================================================
# Report mode
# =============================================================

@test "token-budget: report mode exits 0 even with a skill over cap" {
  _skill big 9000
  run "$BUDGET" --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OVER"* ]] || false
}

@test "token-budget: report names both the file total and the session floor" {
  _skill small 100
  run "$BUDGET" --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Files:"* ]] || false
  [[ "$output" == *"Descriptions:"* ]] || false
}

@test "token-budget: B001 on an unknown argument" {
  run "$BUDGET" --nope
  [ "$status" -eq 2 ]
}

@test "token-budget: B002 when the skills dir does not exist" {
  run "$BUDGET" --skills-dir "$TEST_TEMP_DIR/nope"
  [ "$status" -eq 2 ]
}

@test "token-budget: B001 with exit 2 when --skills-dir has no value" {
  run "$BUDGET" --skills-dir
  [ "$status" -eq 2 ]
  [[ "$output" == *"B001"* ]] || false
}

@test "token-budget: a non-ASCII description is measured in bytes" {
  _skill ascii 100
  run "$BUDGET" --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
  local ascii_desc
  ascii_desc="$(printf '%s\n' "$output" | awk '$1 == "ascii" { print $5 }')"

  rm -rf "${SKILLS:?}/ascii"
  mkdir -p "$SKILLS/wide"
  printf -- '---\nname: wide\ndescription: A test skill \xc3\xa9\xc3\xa9.\n---\n\n# wide\n\nbody\n' \
    > "$SKILLS/wide/SKILL.md"
  run "$BUDGET" --skills-dir "$SKILLS"
  [ "$status" -eq 0 ]
  local wide_desc
  wide_desc="$(printf '%s\n' "$output" | awk '$1 == "wide" { print $5 }')"

  # "A test skill." is 13 bytes; "A test skill ee." with two two-byte accented
  # characters is 18. A character count would report 16 and hide the cost.
  [ "$ascii_desc" -eq 13 ]
  [ "$wide_desc" -eq 18 ]
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
  [[ "$output" == *"bare.sh"* ]] || false
}

@test "check-script-headers: a .bash script with no header fails" {
  mkdir -p "$TEST_TEMP_DIR/s"
  printf '#!/usr/bin/env bash\necho hi\n' > "$TEST_TEMP_DIR/s/bare.bash"
  run "$HEADERS" "$TEST_TEMP_DIR/s"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bare.bash"* ]] || false
}

@test "check-script-headers: a script with a header passes" {
  mkdir -p "$TEST_TEMP_DIR/s"
  printf '#!/usr/bin/env bash\n#\n# ok.sh — does a thing.\n#\n# Usage: ok.sh\n#\n# Exit codes: 0\n\necho hi\n' > "$TEST_TEMP_DIR/s/ok.sh"
  run "$HEADERS" "$TEST_TEMP_DIR/s"
  [ "$status" -eq 0 ]
}
