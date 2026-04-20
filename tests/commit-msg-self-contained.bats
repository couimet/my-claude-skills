#!/usr/bin/env bats

load test_helper

SKILL="$PROJECT_ROOT/skills/commit-msg/SKILL.md"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  [ -f "$SKILL" ] || {
    echo "SKILL file not found: $SKILL" >&2
    return 1
  }
}

# =============================================================
# Self-contained: no foundation skill cross-references
# =============================================================

@test "commit-msg skill: does not cross-reference /issue-context" {
  ! grep -q "/issue-context" "$SKILL"
}

# =============================================================
# Inlined branch detection and auto-number invocation
# =============================================================

@test "commit-msg skill: inlines git branch --show-current" {
  grep -q "git branch --show-current" "$SKILL"
}

@test "commit-msg skill: inlines auto-number.sh invocation" {
  grep -q "skills/auto-number/auto-number.sh" "$SKILL"
}

@test "commit-msg skill: auto-number call uses --mkdir flag for fresh checkouts" {
  grep "auto-number.sh" "$SKILL" | grep -q -- "--mkdir"
}

@test "commit-msg skill: auto-number call filters to *.txt files" {
  grep "auto-number.sh" "$SKILL" | grep -q -- '--glob "\*\.txt"'
}

# =============================================================
# Both directory contexts documented
# =============================================================

@test "commit-msg skill: documents issue-scoped directory path" {
  grep -q '\.claude-work/issues/.*commit-msgs/' "$SKILL"
}

@test "commit-msg skill: documents flat-root directory path" {
  grep -q '\.claude-work/commit-msgs/' "$SKILL"
}
