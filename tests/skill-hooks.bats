#!/usr/bin/env bats

load test_helper

# =============================================================
# Skill-hooks foundation skill
# =============================================================

@test "skill-hooks: file exists" {
  [ -f "$PROJECT_ROOT/skills/skill-hooks/SKILL.md" ]
}

@test "skill-hooks: has name field" {
  grep -q "^name: skill-hooks$" "$PROJECT_ROOT/skills/skill-hooks/SKILL.md"
}

@test "skill-hooks: is a foundation skill (user-invocable: false)" {
  grep -q "user-invocable: false" "$PROJECT_ROOT/skills/skill-hooks/SKILL.md"
}

@test "skill-hooks: points to ADR" {
  grep -q "001-skill-extension-hooks" "$PROJECT_ROOT/skills/skill-hooks/SKILL.md"
}

# =============================================================
# start-issue hook reference
# =============================================================

@test "start-issue skill: references /start-issue-hook" {
  grep -q "/start-issue-hook" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "start-issue skill: hook reference appears after context gathering (Step 3)" {
  # The hook reference should appear after the Step 3 header and before Step 4
  STEP3_LINE=$(grep -n "^## Step 3: Gather Full Context" "$PROJECT_ROOT/skills/start-issue/SKILL.md" | cut -d: -f1)
  STEP4_LINE=$(grep -n "^## Step 4: Create Implementation Plan" "$PROJECT_ROOT/skills/start-issue/SKILL.md" | cut -d: -f1)
  HOOK_LINE=$(grep -n "/start-issue-hook" "$PROJECT_ROOT/skills/start-issue/SKILL.md" | cut -d: -f1)

  [ "$HOOK_LINE" -gt "$STEP3_LINE" ]
  [ "$HOOK_LINE" -lt "$STEP4_LINE" ]
}

# =============================================================
# finish-issue hook references
# =============================================================

@test "finish-issue skill: references /finish-issue-hook" {
  grep -q "/finish-issue-hook" "$PROJECT_ROOT/skills/finish-issue/SKILL.md"
}

@test "finish-issue skill: hook reference appears in verification (Step 2)" {
  STEP2_LINE=$(grep -n "^## Step 2: Pre-PR Verification" "$PROJECT_ROOT/skills/finish-issue/SKILL.md" | cut -d: -f1)
  STEP3_LINE=$(grep -n "^## Step 3: Documentation Review" "$PROJECT_ROOT/skills/finish-issue/SKILL.md" | cut -d: -f1)
  HOOK_LINE=$(grep -n "/finish-issue-hook" "$PROJECT_ROOT/skills/finish-issue/SKILL.md" | cut -d: -f1)

  [ "$HOOK_LINE" -gt "$STEP2_LINE" ]
  [ "$HOOK_LINE" -lt "$STEP3_LINE" ]
}

@test "finish-issue skill: has exactly one /finish-issue-hook reference" {
  COUNT=$(grep -c "/finish-issue-hook" "$PROJECT_ROOT/skills/finish-issue/SKILL.md")
  [ "$COUNT" -eq 1 ]
}

# =============================================================
# start-side-quest hook reference
# =============================================================

@test "start-side-quest skill: references /start-side-quest-hook" {
  grep -q "/start-side-quest-hook" "$PROJECT_ROOT/skills/start-side-quest/SKILL.md"
}

@test "start-side-quest skill: hook reference appears after branch creation (Step 2) and before plan generation (Step 3)" {
  STEP2_LINE=$(grep -n "^## Step 2: Create Side-Quest Branch" "$PROJECT_ROOT/skills/start-side-quest/SKILL.md" | cut -d: -f1)
  STEP3_LINE=$(grep -n "^## Step 3: Create Implementation Working Document" "$PROJECT_ROOT/skills/start-side-quest/SKILL.md" | cut -d: -f1)
  HOOK_LINE=$(grep -n "/start-side-quest-hook" "$PROJECT_ROOT/skills/start-side-quest/SKILL.md" | cut -d: -f1)

  [ "$HOOK_LINE" -gt "$STEP2_LINE" ]
  [ "$HOOK_LINE" -lt "$STEP3_LINE" ]
}

# =============================================================
# Cross-reference consistency
# =============================================================

@test "skill-hooks foundation skill is referenced from start-issue" {
  grep -q "/skill-hooks" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "skill-hooks foundation skill is referenced from start-side-quest" {
  grep -q "/skill-hooks" "$PROJECT_ROOT/skills/start-side-quest/SKILL.md"
}
