#!/usr/bin/env bats

load test_helper

SKILL="$PROJECT_ROOT/skills/concise-output/SKILL.md"

# =============================================================
# Front matter
# =============================================================

@test "concise-output skill: file exists" {
  [ -f "$SKILL" ]
}

@test "concise-output skill: has name field" {
  grep -q "^name: concise-output$" "$SKILL"
}

@test "concise-output skill: is user-invocable (user-invocable: true)" {
  grep -q "user-invocable: true" "$SKILL"
}

@test "concise-output skill: has argument-hint field" {
  grep -q "^argument-hint:" "$SKILL"
}

@test "concise-output skill: has description field" {
  grep -q "^description:" "$SKILL"
}

# =============================================================
# asd-ste100 integration and graceful degradation
# =============================================================

@test "concise-output skill: references the external /asd-ste100 skill" {
  grep -q "/asd-ste100" "$SKILL"
}

@test "concise-output skill: contains a built-in fallback for when asd-ste100 is absent" {
  grep -q "Graceful degradation" "$SKILL"
}

@test "concise-output skill: fallback applies when asd-ste100 is installed but cannot load or invoke" {
  grep -q "cannot load or invoke" "$SKILL"
}

@test "concise-output skill: is wired from prose-style" {
  grep -q "/concise-output" "$PROJECT_ROOT/skills/prose-style/SKILL.md"
}

@test "concise-output skill: note is wired to /prose-style" {
  grep -q "/prose-style" "$PROJECT_ROOT/skills/note/SKILL.md"
}

@test "concise-output skill: the three auto-consult descriptions contain no semicolons" {
  for skill in prose-style note concise-output; do
    ! grep -q '^description:.*;' "$PROJECT_ROOT/skills/$skill/SKILL.md"
  done
}
