#!/usr/bin/env bats

load test_helper

# =============================================================
# Standardized draft format: the /draft-issue writer, the
# issue-draft-reader reader, and the two creation skills must
# agree on one field vocabulary and one reading contract.
# Assertions run against the real skills/ tree.
# =============================================================

SKILLS="$PROJECT_ROOT/skills"

DRAFT="$SKILLS/draft-issue/SKILL.md"
READER="$SKILLS/issue-draft-reader/SKILL.md"
GH="$SKILLS/create-github-issue/SKILL.md"
JIRA="$SKILLS/create-jira-issue/SKILL.md"

# The canonical front-matter field set shared by writer and reader.
FIELDS="target-repo target-project issue-type assignee like parent blocked-by is-blocking"

# assert_reader_table_field <field> — the reader documents the field as a
# row in its Front-Matter Fields table.
assert_reader_table_field() {
  local field="$1"
  grep -q "^| \`$field\` |" "$READER"
}

# assert_draft_template_field <field> — the draft-issue scaffold carries the
# field as a commented line in its field-reference template.
assert_draft_template_field() {
  local field="$1"
  grep -q "^# $field:" "$DRAFT"
}

# =============================================================
# /draft-issue — the writer
# =============================================================

@test "draft-issue: skill exists with front matter and argument hint" {
  [ -f "$DRAFT" ]
  grep -q '^name: draft-issue' "$DRAFT"
  grep -q '^argument-hint:' "$DRAFT"
}

@test "draft-issue: defines every canonical field" {
  for f in $FIELDS; do
    assert_draft_template_field "$f"
  done
}

@test "draft-issue: describes the front-matter-over-heading shape" {
  grep -q 'front-matter block over a markdown body' "$DRAFT"
  grep -q "title is the body's first .#. heading" "$DRAFT"
}

@test "draft-issue: writes the draft through /note" {
  grep -q 'Follow `/note`' "$DRAFT"
}

@test "draft-issue: scaffolds as a note-typed file, not a new placement" {
  grep -q 'Drafts are `note`-typed files' "$DRAFT"
}

@test "draft-issue: forbids copying the example body into a draft" {
  grep -q 'Never copy the example body text' "$DRAFT"
}

@test "draft-issue: example draft shows active fields over a # heading" {
  grep -q '^# Draft a feature with a standard local format' "$DRAFT"
}

# =============================================================
# /draft-issue — the /g2q thoroughness gate
# =============================================================

@test "draft-issue: grills the composed draft through /g2q" {
  grep -q 'Run `/g2q` on the composed draft' "$DRAFT"
  grep -q 'passing the title and body as its topic' "$DRAFT"
}

@test "draft-issue: folds answers in until none are raised" {
  grep -q 'until it reports no questions raised' "$DRAFT"
}

@test "draft-issue: does not write the note until the grill is clean" {
  grep -q 'The draft note is not written until this grill is clean' "$DRAFT"
}

@test "draft-issue: invites the author to compose a body before grilling" {
  grep -q 'invite the author to compose the body now' "$DRAFT"
}

@test "draft-issue: the manifest routes the grill to /g2q" {
  grep -q '"draft-issue=note g2q"' "$PROJECT_ROOT/scripts/check-transitive-tools.sh"
}

# =============================================================
# issue-draft-reader — the reader
# =============================================================

@test "reader: is a foundation skill" {
  grep -q '^user-invocable: false' "$READER"
}

@test "reader: defines every canonical field" {
  for f in $FIELDS; do
    assert_reader_table_field "$f"
  done
}

@test "reader: validates the opening --- fence before reading fields" {
  grep -q 'first non-empty line must be the .---. opening fence' "$READER"
}

@test "reader: routes an unstandardized file through /draft-issue" {
  grep -q 'Run the conversion command /draft-issue' "$READER"
}

@test "reader: front matter is never filed" {
  grep -q 'never filed' "$READER"
}

@test "reader: no marker-line collection vocabulary remains" {
  ! grep -q '\*\*Target repo:\*\*' "$READER"
  ! grep -q '\*\*Like:\*\*' "$READER"
  ! grep -q '\*\*Parent:\*\*' "$READER"
}

# =============================================================
# The two creation skills — consumers
# =============================================================

@test "create-github-issue: reads the draft through the reader" {
  grep -q 'Follow `/issue-draft-reader`' "$GH"
}

@test "create-jira-issue: reads the draft through the reader" {
  grep -q 'Follow `/issue-draft-reader`' "$JIRA"
}

@test "create-github-issue: relationships come from explicit fields, not prose" {
  grep -q 'no natural-language scanning happens' "$GH"
  grep -q 'blocked-by' "$GH"
  grep -q 'is-blocking' "$GH"
}

@test "create-jira-issue: project and type resolve from the same fields" {
  grep -q '`target-project`' "$JIRA"
  grep -q '`issue-type`' "$JIRA"
}

# =============================================================
# Writer/reader/consumer agreement
# =============================================================

@test "draft and reader name the same field set" {
  for f in $FIELDS; do
    assert_draft_template_field "$f"
    assert_reader_table_field "$f"
  done
}

@test "release-article handoff matches the draft shape creation reads" {
  grep -q 'standardized draft shape that `/create-github-issue` reads' "$SKILLS/release-article/SKILL.md"
  grep -q 'target-repo: couimet/couimet.github.io' "$SKILLS/release-article/SKILL.md"
}
