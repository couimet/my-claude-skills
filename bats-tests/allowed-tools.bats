#!/usr/bin/env bats

load test_helper

# =============================================================
# Transitive coverage (skills that invoke /note must declare the
# permission /note requires) is now enforced by
# scripts/check-transitive-tools.sh via bats-tests/transitive-tools.bats.
# The tests below cover only the cases the validator does not:
# skills that call mkdir -p directly.
# =============================================================

@test "allowed-tools: breadcrumb has Bash(mkdir -p *) (writes to .claude-work/ directories)" {
  grep "^allowed-tools:" "$PROJECT_ROOT/skills/breadcrumb/SKILL.md" | grep -q 'Bash(mkdir -p \*)'
}

@test "allowed-tools: note has Bash(mkdir -p *) (calls mkdir -p directly)" {
  grep "^allowed-tools:" "$PROJECT_ROOT/skills/note/SKILL.md" | grep -q 'Bash(mkdir -p \*)'
}

# =============================================================
# Regression: skills that should NOT have unrestricted Bash
# =============================================================

@test "allowed-tools: start-issue does not have unrestricted Bash(*)" {
  ! grep "^allowed-tools:" "$PROJECT_ROOT/skills/start-issue/SKILL.md" | grep -q 'Bash(\*)'
}

@test "allowed-tools: finish-issue does not have unrestricted Bash(*)" {
  ! grep "^allowed-tools:" "$PROJECT_ROOT/skills/finish-issue/SKILL.md" | grep -q 'Bash(\*)'
}

@test "allowed-tools: breadcrumb does not have unrestricted Bash(*)" {
  ! grep "^allowed-tools:" "$PROJECT_ROOT/skills/breadcrumb/SKILL.md" | grep -q 'Bash(\*)'
}

@test "allowed-tools: start-side-quest does not have unrestricted Bash(*)" {
  ! grep "^allowed-tools:" "$PROJECT_ROOT/skills/start-side-quest/SKILL.md" | grep -q 'Bash(\*)'
}

@test "allowed-tools: tackle-pr-comment does not have unrestricted Bash(*)" {
  ! grep "^allowed-tools:" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md" | grep -q 'Bash(\*)'
}
