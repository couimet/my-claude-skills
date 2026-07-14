#!/usr/bin/env bats

load test_helper

# =============================================================
# Transitive coverage: skills that invoke /note must declare
# Bash(mkdir -p *) because /note calls mkdir -p to create the
# target directory before writing.
# =============================================================

@test "allowed-tools: start-issue has Bash(mkdir -p *) (invokes /note transitively)" {
  grep "^allowed-tools:" "$PROJECT_ROOT/skills/start-issue/SKILL.md" | grep -q 'Bash(mkdir -p \*)'
}

@test "allowed-tools: finish-issue has Bash(mkdir -p *) (invokes /note transitively)" {
  grep "^allowed-tools:" "$PROJECT_ROOT/skills/finish-issue/SKILL.md" | grep -q 'Bash(mkdir -p \*)'
}

@test "allowed-tools: start-side-quest has Bash(mkdir -p *) (invokes /note transitively)" {
  grep "^allowed-tools:" "$PROJECT_ROOT/skills/start-side-quest/SKILL.md" | grep -q 'Bash(mkdir -p \*)'
}

@test "allowed-tools: tackle-pr-comment has Bash(mkdir -p *) (invokes /note transitively)" {
  grep "^allowed-tools:" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md" | grep -q 'Bash(mkdir -p \*)'
}

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
