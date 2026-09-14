#!/usr/bin/env bats

load test_helper

SKILL="$PROJECT_ROOT/skills/note/SKILL.md"

# =============================================================
# Front matter
# =============================================================

@test "note skill: has name field" {
  grep -q "^name: note$" "$SKILL"
}

@test "note skill: is user-invocable (no user-invocable: false)" {
  ! grep -q "user-invocable: false" "$SKILL"
}

@test "note skill: has description field" {
  grep -q "^description:" "$SKILL"
}

@test "note skill: has argument-hint field" {
  grep -q "^argument-hint:" "$SKILL"
}

@test "note skill: allowed-tools includes Write" {
  grep "^allowed-tools:" "$SKILL" | grep -q "Write"
}

@test "note skill: allowed-tools does not include unrestricted Bash" {
  ! grep "^allowed-tools:" "$SKILL" | grep -q 'Bash(\*)'
}

# =============================================================
# Self-contained: no foundation skill cross-references
# =============================================================

@test "note skill: references issue-context scripts for path resolution" {
  grep -q "issue-context/target-path.sh" "$SKILL"
}

@test "note skill: does not cross-reference /ensure-gitignore" {
  ! grep -q "/ensure-gitignore" "$SKILL"
}

@test "note skill: does not cross-reference /code-ref" {
  ! grep -q "/code-ref" "$SKILL"
}

@test "note skill: does not cross-reference /github-ref" {
  ! grep -q "/github-ref" "$SKILL"
}

# =============================================================
# Path resolution is delegated, not described.
#
# These tests used to assert that this skill documented the filename format,
# the extension, and the directory routing. It owned none of those; it only
# restated them. Per docs/ADR/004 the skill states the properties it relies
# on and cross-references the contract. The format itself is enforced in
# bats-tests/script-contract-boundary.bats across every consumer, so
# asserting its absence here would just duplicate that check.
# =============================================================

# Regression, issues/261: the timestamp used to be derived in prose by telling
# the model to run `date`, which is how filenames with a wrong date and no time
# reached .claude-work/. The prose guard against that was dropped once the
# permission was, because withholding Bash(date *) is a barrier the model
# cannot talk itself past, and prose is not.
@test "note skill: cannot derive a timestamp itself" {
  ! grep -q 'date +%Y%m%d-%H%M%S' "$SKILL"
  ! grep "^allowed-tools:" "$SKILL" | grep -q 'Bash(date \*)'
}

@test "note skill: delegates the whole path to target-path.sh" {
  grep -q "issue-context/target-path.sh --type notes" "$SKILL"
  ! grep -q "issue-context/get-issue-folder-path.sh" "$SKILL"
  ! grep -q "issue-context/branch-issue-id.sh" "$SKILL"
  ! grep -q "issue-context/claude-work-root.sh" "$SKILL"
}

@test "note skill: points at the contract rather than restating it" {
  grep -q "/issue-context" "$SKILL"
}

@test "note skill: does not build its own path" {
  ! grep "^allowed-tools:" "$SKILL" | grep -q 'Bash(mkdir -p \*)'
}
