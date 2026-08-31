#!/usr/bin/env bats

load test_helper

# =============================================================
# g2q skill: front matter
# =============================================================

@test "g2q: file exists" {
  [ -f "$PROJECT_ROOT/skills/g2q/SKILL.md" ]
}

@test "g2q: has name field" {
  grep -q "^name: g2q$" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

@test "g2q: is user-invocable" {
  grep -q "user-invocable: true" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

@test "g2q: has argument-hint" {
  grep -q "^argument-hint:" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

@test "g2q: allowed-tools cover the /question transitive chain" {
  grep "^allowed-tools:" "$PROJECT_ROOT/skills/g2q/SKILL.md" | grep -q 'Bash(\*/skills/issue-context/target-path.sh \*)'
  grep "^allowed-tools:" "$PROJECT_ROOT/skills/g2q/SKILL.md" | grep -q 'Bash(\*/skills/ensure-gitignore/ensure-gitignore.sh \*)'
}

# =============================================================
# Composite skills reference g2q at draft time
# =============================================================

@test "start-issue skill: references /g2q" {
  grep -q "/g2q" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "start-issue skill: grill reference appears in Step 4 (after the plan step, before the report step)" {
  STEP4_LINE=$(grep -n "^## Step 4: Create Implementation Plan" "$PROJECT_ROOT/skills/start-issue/SKILL.md" | cut -d: -f1)
  STEP5_LINE=$(grep -n "^## Step 5: Report Status" "$PROJECT_ROOT/skills/start-issue/SKILL.md" | cut -d: -f1)
  GRILL_LINE=$(grep -n "/g2q" "$PROJECT_ROOT/skills/start-issue/SKILL.md" | head -1 | cut -d: -f1)

  [ "$GRILL_LINE" -gt "$STEP4_LINE" ]
  [ "$GRILL_LINE" -lt "$STEP5_LINE" ]
}

@test "start-issue skill: has Step 6 finalize step" {
  grep -q "^## Step 6: Finalize the Plan After Answers" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "tackle-pr-comment skill: references /g2q" {
  grep -q "/g2q" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

@test "tackle-pr-comment skill: grill reference appears in Step 5 (after the working-doc step, before the report step)" {
  STEP5_LINE=$(grep -n "^## Step 5: Create Implementation Working Document" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md" | cut -d: -f1)
  STEP6_LINE=$(grep -n "^## Step 6: Report and Stop" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md" | cut -d: -f1)
  GRILL_LINE=$(grep -n "/g2q" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md" | head -1 | cut -d: -f1)

  [ "$GRILL_LINE" -gt "$STEP5_LINE" ]
  [ "$GRILL_LINE" -lt "$STEP6_LINE" ]
}

@test "tackle-pr-comment skill: has Step 7 finalize step" {
  grep -q "^## Step 7: Finalize the Plan After Answers" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

# =============================================================
# Pending-stub gating contract
# =============================================================

@test "start-issue skill: pending-stub banner names the awaiting-answers contract" {
  grep -q "Production of this plan awaits answers to the questions in" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "tackle-pr-comment skill: pending-stub banner names the awaiting-answers contract" {
  grep -q "Production of this plan awaits answers to the questions in" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

@test "start-issue skill: pending stub records the draft path" {
  grep -q "Draft: <absolute draft path>" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "tackle-pr-comment skill: pending stub records the draft path" {
  grep -q "Draft: <absolute draft path>" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

@test "start-issue skill: Step 6 reads the draft together with the questions file" {
  grep -q "the draft at the path recorded in the stub" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "tackle-pr-comment skill: Step 7 reads the draft together with the questions file" {
  grep -q "the draft at the path recorded in the stub" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

# =============================================================
# /question <-> /g2q delegation contract
# =============================================================

@test "question skill: argument-hint advertises --format-only" {
  grep -q "argument-hint: '\[--format-only\] <topic>'" "$PROJECT_ROOT/skills/question/SKILL.md"
}

@test "question skill: delegates the challenge to /g2q" {
  grep -q "/g2q" "$PROJECT_ROOT/skills/question/SKILL.md"
}

@test "question skill: no longer owns the single source of trigger truth" {
  run grep -q "single source of trigger truth" "$PROJECT_ROOT/skills/question/SKILL.md"
  [ "$status" -ne 0 ]
}

@test "g2q skill: has the trigger predicate section" {
  grep -q "^## Trigger Predicate" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

@test "start-issue skill: points the trigger predicate at /g2q" {
  grep -q "/g2q.*single source of trigger truth" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "tackle-pr-comment skill: points the trigger predicate at /g2q" {
  grep -q "/g2q.*single source of trigger truth" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

@test "g2q skill: creates the questions file via /question --format-only" {
  grep -q "/question --format-only" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}
