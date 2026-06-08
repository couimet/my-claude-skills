#!/usr/bin/env bats

load test_helper

SKILL="$PROJECT_ROOT/skills/pre-write/SKILL.md"

# =============================================================
# Front matter
# =============================================================

@test "pre-write skill: file exists" {
  [ -f "$SKILL" ]
}

@test "pre-write skill: has name field" {
  grep -q "^name: pre-write$" "$SKILL"
}

@test "pre-write skill: is a foundation skill (user-invocable: false)" {
  grep -q "user-invocable: false" "$SKILL"
}

@test "pre-write skill: has description field" {
  grep -q "^description:" "$SKILL"
}

# =============================================================
# Content: rule correctness
# =============================================================

@test "pre-write skill: mentions /question as escape hatch" {
  grep -q "/question" "$SKILL"
}

@test "pre-write skill: names at least one forbidden phrase" {
  grep -qE '"oh wait"|"I now realize"|self-correction' "$SKILL"
}

# =============================================================
# References in content-generating skills
# =============================================================

@test "note skill: references /pre-write" {
  grep -q "/pre-write" "$PROJECT_ROOT/skills/note/SKILL.md"
}

@test "scratchpad skill: references /pre-write" {
  grep -q "/pre-write" "$PROJECT_ROOT/skills/scratchpad/SKILL.md"
}

@test "question skill: references /pre-write" {
  grep -q "/pre-write" "$PROJECT_ROOT/skills/question/SKILL.md"
}

@test "commit-msg skill: references /pre-write" {
  grep -q "/pre-write" "$PROJECT_ROOT/skills/commit-msg/SKILL.md"
}

@test "finish-issue skill: references /pre-write" {
  grep -q "/pre-write" "$PROJECT_ROOT/skills/finish-issue/SKILL.md"
}

@test "start-issue skill: references /pre-write" {
  grep -q "/pre-write" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}
