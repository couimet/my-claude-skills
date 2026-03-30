#!/usr/bin/env bats

load test_helper

SKILL="$PROJECT_ROOT/skills/file-placement/SKILL.md"

# =============================================================
# Front matter
# =============================================================

@test "file-placement skill: has name field" {
  grep -q "^name: file-placement$" "$SKILL"
}

@test "file-placement skill: is a foundation skill (user-invocable: false)" {
  grep -q "user-invocable: false" "$SKILL"
}

@test "file-placement skill: has description field" {
  grep -q "^description:" "$SKILL"
}

# =============================================================
# Decision tree structure
# =============================================================

@test "file-placement skill: decision tree has Question/Destination/Skill headers" {
  grep -q "| Question | Destination | Skill |" "$SKILL"
}

# =============================================================
# Decision tree rows: each file type routes to correct destination
# =============================================================

@test "file-placement skill: questions route to .claude-work/questions/" {
  grep "question" "$SKILL" | grep -q '\.claude-work/questions/'
}

@test "file-placement skill: questions reference /question skill" {
  grep '\.claude-work/questions/' "$SKILL" | grep -q '/question'
}

@test "file-placement skill: commit messages route to .claude-work/commit-msgs/" {
  grep "commit message" "$SKILL" | grep -q '\.claude-work/commit-msgs/'
}

@test "file-placement skill: commit messages reference /commit-msg skill" {
  grep '\.claude-work/commit-msgs/' "$SKILL" | grep -q '/commit-msg'
}

@test "file-placement skill: temporary working documents route to .claude-work/scratchpads/" {
  grep "temporary working document" "$SKILL" | grep -q '\.claude-work/scratchpads/'
}

@test "file-placement skill: temporary working documents reference /scratchpad skill" {
  grep '\.claude-work/scratchpads/' "$SKILL" | grep -q '/scratchpad'
}

@test "file-placement skill: notes route to .claude-work/notes/" {
  grep "note, finding" "$SKILL" | grep -q '\.claude-work/notes/'
}

@test "file-placement skill: notes reference /note skill" {
  grep '\.claude-work/notes/' "$SKILL" | grep -q '/note'
}

@test "file-placement skill: issue breadcrumbs route to .claude-work/issues/<ID>/breadcrumb.md" {
  grep "note during issue" "$SKILL" | grep -q '\.claude-work/issues/.*breadcrumb\.md'
}

@test "file-placement skill: issue breadcrumbs reference /breadcrumb skill" {
  grep 'breadcrumb\.md' "$SKILL" | grep -q '/breadcrumb'
}

@test "file-placement skill: permanent documentation routes to docs/" {
  grep "permanent documentation" "$SKILL" | grep -q 'docs/'
}

# =============================================================
# Decision tree completeness: expected row count
# =============================================================

@test "file-placement skill: decision tree has exactly 6 routing rows" {
  # Count table rows excluding the header and separator lines
  count="$(grep -c '^| Is it' "$SKILL")"
  [ "$count" -eq 6 ]
}

# =============================================================
# Ephemeral path rule
# =============================================================

@test "file-placement skill: documents ephemeral path rule" {
  grep -q "\.claude-work.*must never appear in commits" "$SKILL"
}
