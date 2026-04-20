#!/usr/bin/env bats

load test_helper

SKILL="$PROJECT_ROOT/skills/question/SKILL.md"

# =============================================================
# Self-contained: no foundation skill cross-references
# =============================================================

@test "question skill: does not cross-reference /issue-context" {
  ! grep -q "/issue-context" "$SKILL"
}

# =============================================================
# Inlined branch detection and auto-number invocation
# =============================================================

@test "question skill: inlines git branch --show-current" {
  grep -q "git branch --show-current" "$SKILL"
}

@test "question skill: inlines auto-number.sh invocation" {
  grep -q "skills/auto-number/auto-number.sh" "$SKILL"
}

@test "question skill: auto-number call uses --mkdir flag for fresh checkouts" {
  grep "auto-number.sh" "$SKILL" | grep -q -- "--mkdir"
}

@test "question skill: auto-number call filters to *.txt files" {
  grep "auto-number.sh" "$SKILL" | grep -q -- '--glob "\*\.txt"'
}

# =============================================================
# Both directory contexts documented
# =============================================================

@test "question skill: documents issue-scoped directory path" {
  grep -q '\.claude-work/issues/.*questions/' "$SKILL"
}

@test "question skill: documents flat-root directory path" {
  grep -q '\.claude-work/questions/' "$SKILL"
}
