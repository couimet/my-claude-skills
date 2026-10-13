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
FIELDS="target-repo target-project issue-type assignee like parent blocked-by is-blocking jira-fields"

# assert_reader_table_field <field> — the reader documents the field as a
# row in its Front-Matter Fields table.
assert_reader_table_field() {
  local field="$1"
  grep -qE "^\\| \`$field\` +\\|" "$READER"
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
# /draft-issue — machine fields are inferred, not asked
# =============================================================

@test "draft-issue: Step 4 infers machine fields" {
  grep -q '^## Step 4: Infer Machine Fields' "$DRAFT"
  ! grep -q 'Collect Machine Fields' "$DRAFT"
}

@test "draft-issue: asks nothing when the scan infers no field" {
  grep -q 'When the scan finds nothing, ask nothing and keep the commented template' "$DRAFT"
}

@test "draft-issue: proposes inferred fields in one AskUserQuestion" {
  grep -q 'ask one `AskUserQuestion` that proposes the inferred fields' "$DRAFT"
  grep -q '`target-repo`: a statement that the issue lands in another' "$DRAFT"
  grep -q '`blocked-by`: an issue or ticket that the work waits on' "$DRAFT"
  grep -q '`is-blocking`: an issue or ticket that the work unblocks' "$DRAFT"
}

@test "draft-issue: an import with active front matter asks nothing" {
  grep -q 'An import that already has active front matter keeps its fields, and this step asks nothing' "$DRAFT"
}

@test "draft-issue: report says when every field is at its default" {
  grep -q 'All fields are at their defaults; edit the file to add a parent or a dependency.' "$DRAFT"
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

@test "reader: reads an indented Name: value block as a map" {
  grep -q 'reads as a map from each name to its value' "$READER"
}

@test "reader: asks about each local-only file reference" {
  grep -q 'for each local-only reference, ask the user with `AskUserQuestion`' "$READER"
  grep -q 'inline the file content as a fenced code block' "$READER"
}

@test "reader: reports changed local file references under a heading" {
  grep -q '`Changed local file references:` heading' "$READER"
  grep -q 'When you change nothing, print nothing' "$READER"
}

@test "reader: a tracked repo-relative path is not local-only" {
  grep -q 'git ls-files --error-unmatch "<path>"' "$READER"
  grep -q 'A repo-relative path that the repository tracks passes' "$READER"
}

@test "reader and both creation skills declare the local-file prompt tools" {
  for f in "$READER" "$GH" "$JIRA"; do
    grep -q '^allowed-tools:.*AskUserQuestion' "$f"
    grep -q '^allowed-tools:.*Bash(git ls-files \*)' "$f"
  done
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

@test "create-jira-issue: fetches required-field metadata for every draft" {
  grep -q 'Fetch the field metadata for every draft' "$JIRA"
  grep -q 'Pass `requiredFieldsOnly: true` when the draft has no `like` field and no `jira-fields` field' "$JIRA"
}

@test "create-jira-issue: asks for each required field that nothing sets" {
  grep -q 'Ask for each required field that nothing sets' "$JIRA"
  grep -q 'This check runs before the create call' "$JIRA"
}

@test "create-jira-issue: resolves jira-fields by display name" {
  grep -q 'When a `jira-fields` field exists, resolve each entry by display name' "$JIRA"
  grep -q 'When a name matches no field, STOP and print the field names' "$JIRA"
}

@test "create-jira-issue: files task lists as ADF and verifies them" {
  grep -q 'use `contentFormat: "adf"`' "$JIRA"
  grep -q 'confirm that the description holds a `taskList` node' "$JIRA"
  grep -q '^allowed-tools:.*mcp__atlassian__editJiraIssue' "$JIRA"
  ! grep -q 'task-list checkboxes do not carry over' "$JIRA"
}

@test "create-jira-issue: the expected-hash argument is optional" {
  grep -q '^argument-hint: <file-path-or-title> \[--expect-sha256 <hex>\]' "$JIRA"
  grep -q '\*\*No flag:\*\* skip this check' "$JIRA"
  grep -q '^allowed-tools:.*Bash(\*/skills/create-jira-issue/draft-sha256.sh \*)' "$JIRA"
}

@test "create-jira-issue: a hash mismatch stops before the reader and the create" {
  grep -q 'When they differ, STOP before the reader runs' "$JIRA"
  grep -q 'the draft changed after its review' "$JIRA"
}

@test "create-jira-issue: an inline title with an expected hash stops" {
  grep -q '\*\*The flag with an inline title:\*\* STOP' "$JIRA"
}

@test "create-jira-issue: a matching hash runs the reader in strict mode" {
  grep -q 'tell the reader to run in strict mode' "$JIRA"
}

@test "reader: strict mode stops instead of changing approved text" {
  grep -q 'In strict mode the reader changes nothing in the body' "$READER"
  grep -q 'The filed text would differ from the approved text' "$READER"
}

@test "draft-sha256: the documented span matches the plugin rule" {
  local script="$SKILLS/create-jira-issue/draft-sha256.sh"
  grep -q 'Skip the front-matter block' "$script"
  grep -q 'Remove leading lines that hold only spaces and tabs' "$script"
  grep -q 'Print the SHA-256 of a draft.s filed text: its title and body' "$script"
  grep -q 'hashes the title line and the body, without the front matter' "$JIRA"
}

@test "create-jira-issue: reads the ticket back after every create" {
  grep -q '^## Step 6: Read Back the Ticket' "$JIRA"
  grep -q 'Run this step after every create, with or without an expected hash' "$JIRA"
  grep -q 'do not edit or delete the ticket' "$JIRA"
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
