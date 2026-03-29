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

@test "note skill: does not cross-reference /issue-context" {
  ! grep -q "/issue-context" "$SKILL"
}

@test "note skill: does not cross-reference /auto-number" {
  ! grep -q "/auto-number" "$SKILL"
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
# Key content: timestamp naming and branch detection
# =============================================================

@test "note skill: mentions timestamp format YYYYMMDD-HHMMSS" {
  grep -q "YYYYMMDD-HHMMSS" "$SKILL"
}

@test "note skill: uses date command for timestamps" {
  grep -q 'date +%Y%m%d-%H%M%S' "$SKILL"
}

@test "note skill: mentions git branch detection" {
  grep -q "git branch --show-current" "$SKILL"
}

@test "note skill: routes to .claude-work/issues/<ID>/notes/ on issue branches" {
  grep -q '\.claude-work/issues/.*notes/' "$SKILL"
}

@test "note skill: routes to .claude-work/notes/ as fallback" {
  grep -q '\.claude-work/notes/' "$SKILL"
}

@test "note skill: uses .txt extension" {
  grep -q '\.txt' "$SKILL"
}
