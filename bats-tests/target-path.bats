#!/usr/bin/env bats
#
# Tests for skills/issue-context/target-path.sh — resolves the full target
# path for a timestamped working file by combining branch detection, issue-ID
# extraction, slug derivation, and timestamp stamping. Every test runs in a
# fresh git repo with MY_CLAUDE_SKILLS_CONFIG pointed at a temp settings file
# so a developer's real ~/.my-claude-skills/settings.json can never change the
# outcome, and under a stubbed `date` so the emitted stamp is fixed. Without
# the stub every assertion would have to be a regex, and the same-second
# collision case could not be forced at all.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/target-path.sh"

# The stamp every test sees. The script calls `date +%Y%m%d-%H%M%S`, so a stub
# earlier on PATH pins it. bats-tests/shell-coverage.bats stubs kcov and bats
# the same way.
STAMP="20260909-101500"

# Write a stub `date` into the given directory. It answers the script's format
# request with $STAMP and forwards anything else to the real date, so an
# unrelated caller is unaffected.
date_stub() {
  cat > "$1/date" <<STUB
#!/usr/bin/env bash
if [ "\$*" = "+%Y%m%d-%H%M%S" ]; then
  printf '%s\n' "$STAMP"
  exit 0
fi
exec /bin/date "\$@"
STUB
  chmod +x "$1/date"
}

# Run the script with the stub ahead of the inherited PATH. Prepending rather
# than replacing matters: the script also needs git, jq, sed, tr, and mkdir.
run_target_path() {
  run env PATH="$STUB_BIN:$PATH" "$SCRIPT" "$@"
}

# Run the script inside a fresh git repo so branch detection is deterministic.
setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  # Resolve any symlinks (macOS /var → /private/var) so path comparisons
  # against git rev-parse --show-toplevel output match exactly.
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  STUB_BIN="$TEST_TEMP_DIR/stub-bin"
  mkdir -p "$STUB_BIN"
  date_stub "$STUB_BIN"
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  # Pin settings to an empty object so the loader uses the built-in defaults
  # (segment "issues") regardless of the developer's real settings file.
  export MY_CLAUDE_SKILLS_CONFIG="$TEST_TEMP_DIR/settings.json"
  printf '{}\n' > "$MY_CLAUDE_SKILLS_CONFIG"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# ============================================================================
# Issue branches: path includes the issue ID
# ============================================================================

@test "issues/42 → numeric ID, scratchpads type" {
  git checkout -q -b issues/42
  run_target_path --type scratchpads --description "Plan the refactor"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-plan-the-refactor.txt" ]
}

@test "issues/120-extract-numeric-prefix → extracts 120" {
  git checkout -q -b issues/120-audit-cleanup
  run_target_path --type questions --description "Scope question"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/120/questions/$STAMP-scope-question.txt" ]
}

@test "issues/120_with_underscore → extracts 120" {
  git checkout -q -b issues/120_audit
  run_target_path --type scratchpads --description "Test"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/120/scratchpads/$STAMP-test.txt" ]
}

@test "issues/rfc-auth → non-numeric prefix uses full segment" {
  git checkout -q -b issues/rfc-auth
  run_target_path --type commit-msgs --description "Draft message"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/rfc-auth/commit-msgs/$STAMP-draft-message.txt" ]
}

# ============================================================================
# Non-issue branches: path goes to flat root
# ============================================================================

@test "main branch → flat-root placement" {
  # Force the branch name so the test is deterministic regardless of the host's
  # init.defaultBranch setting (which may be master, main, trunk, etc.).
  git checkout -q -B main
  run_target_path --type scratchpads --description "Hello world"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/scratchpads/$STAMP-hello-world.txt" ]
}

@test "side-quest/foo branch → flat-root placement" {
  git checkout -q -b side-quest/foo
  run_target_path --type questions --description "Side quest question"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/questions/$STAMP-side-quest-question.txt" ]
}

# ============================================================================
# Same-second collisions: the stamp gets a -2, -3 disambiguator, never an
# overwrite. The stubbed clock is what makes this reachable — two real calls
# would almost always land in different seconds.
# ============================================================================

@test "same second, same slug → -2 disambiguator instead of overwrite" {
  git checkout -q -b issues/42
  run_target_path --type scratchpads --description "Plan"
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-plan.txt" ]
  # The caller writes the file it was handed; the next call must not reuse it.
  touch "$output"
  run_target_path --type scratchpads --description "Plan"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-plan-2.txt" ]
}

@test "same second, same slug, twice over → -3 after -2 is taken" {
  git checkout -q -b issues/42
  run_target_path --type scratchpads --description "Plan"
  touch "$output"
  run_target_path --type scratchpads --description "Plan"
  touch "$output"
  run_target_path --type scratchpads --description "Plan"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-plan-3.txt" ]
}

@test "same second, different slug → no disambiguator needed" {
  git checkout -q -b issues/42
  run_target_path --type scratchpads --description "First"
  touch "$output"
  run_target_path --type scratchpads --description "Second"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-second.txt" ]
}

# ============================================================================
# Regression, issues/261 Defect 1: the emitted name is a function of the clock
# alone. The retired auto-number.sh read the leading digit run of a sibling as
# its high-water mark, so one date-named file permanently converted a
# directory's sequence to 8-digit pseudo-dates. No sibling is read any more.
# ============================================================================

@test "date-prefixed sibling does not influence the emitted name" {
  git checkout -q -b issues/42
  mkdir -p ".claude-work/issues/42/scratchpads"
  # The exact filename from the issue's reproduction case.
  touch ".claude-work/issues/42/scratchpads/20260902-131841-third.txt"
  run_target_path --type scratchpads --description "Unaffected"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-unaffected.txt" ]
}

@test "NNNN-prefixed leftovers from the retired scheme are ignored" {
  git checkout -q -b issues/42
  mkdir -p ".claude-work/issues/42/scratchpads"
  touch ".claude-work/issues/42/scratchpads/0001-first.txt"
  touch ".claude-work/issues/42/scratchpads/0002-second.txt"
  run_target_path --type scratchpads --description "Third"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-third.txt" ]
}

# ============================================================================
# Slug normalization
# ============================================================================

@test "slug lowercases, hyphenates, and collapses separators" {
  git checkout -q -b issues/42
  run_target_path --type scratchpads --description "Some   MIXED--Case & punctuation!"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-some-mixed-case-punctuation.txt" ]
}

@test "slug trims leading and trailing hyphens" {
  git checkout -q -b issues/42
  run_target_path --type scratchpads --description "  hello world  "
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-hello-world.txt" ]
}

# ============================================================================
# Extension override
# ============================================================================

@test "--ext overrides default txt extension" {
  git checkout -q -B main
  run_target_path --type scratchpads --description "Config" --ext json
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/scratchpads/$STAMP-config.json" ]
}

@test "--ext md still works alongside json" {
  git checkout -q -B main
  run_target_path --type scratchpads --description "Doc" --ext md
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/scratchpads/$STAMP-doc.md" ]
}

# ============================================================================
# --ext validation: reject anything that isn't pure alphanumeric
# ============================================================================

@test "--ext with dots (..) errors with T102" {
  run_target_path --type scratchpads --description "x" --ext ".."
  [ "$status" -eq 1 ]
  [[ "$output" == *"T102"* ]]
}

@test "--ext with path separator errors with T102" {
  run_target_path --type scratchpads --description "x" --ext "foo/bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T102"* ]]
}

@test "--ext with whitespace errors with T102" {
  run_target_path --type scratchpads --description "x" --ext "foo bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T102"* ]]
}

@test "--ext with glob character errors with T102" {
  run_target_path --type scratchpads --description "x" --ext "*"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T102"* ]]
}

@test "--ext with shell metacharacter errors with T102" {
  run_target_path --type scratchpads --description "x" --ext '$(whoami)'
  [ "$status" -eq 1 ]
  [[ "$output" == *"T102"* ]]
}

@test "--ext with hyphen (not alphanumeric) errors with T102" {
  run_target_path --type scratchpads --description "x" --ext "tar-gz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T102"* ]]
}

# ============================================================================
# Side effect: target directory is created
# ============================================================================

@test "--mkdir behavior: target directory is created on first call" {
  git checkout -q -b issues/77
  [ ! -d ".claude-work/issues/77/scratchpads" ]
  run_target_path --type scratchpads --description "First"
  [ "$status" -eq 0 ]
  [ -d ".claude-work/issues/77/scratchpads" ]
}

# ============================================================================
# Error cases
# ============================================================================

@test "missing --type errors with T001" {
  run_target_path --description "test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T001"* ]]
}

@test "missing --description errors with T001" {
  run_target_path --type scratchpads
  [ "$status" -eq 1 ]
  [[ "$output" == *"T001"* ]]
}

@test "notes type on issue branch → issue-scoped notes path" {
  git checkout -q -b issues/42
  run_target_path --type notes --description "Plan the work"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/notes/$STAMP-plan-the-work.txt" ]
}

@test "notes type on main branch → flat-root notes path" {
  git checkout -q -B main
  run_target_path --type notes --description "Quick finding"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/notes/$STAMP-quick-finding.txt" ]
}

@test "invalid --type errors with T100" {
  run_target_path --type bogus --description "test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T100"* ]]
}

@test "unknown flag errors with T002" {
  run_target_path --type scratchpads --description "test" --nonsense
  [ "$status" -eq 1 ]
  [[ "$output" == *"T002"* ]]
}

# ============================================================================
# Linked worktree: output resolves to main checkout, not worktree local
# ============================================================================

@test "linked worktree: output resolves to main checkout .claude-work" {
  # Main checkout stays on the default branch; create a linked worktree
  # on issues/99 so the branch is not already checked out.
  git worktree add "$TEST_TEMP_DIR/wt-linked" -b issues/99 -q
  cd "$TEST_TEMP_DIR/wt-linked"
  run_target_path --type notes --description "from worktree"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/99/notes/$STAMP-from-worktree.txt" ]
  # Worktree directory should NOT have its own .claude-work
  [ ! -d "$TEST_TEMP_DIR/wt-linked/.claude-work" ]
}

# ============================================================================
# Repo-root anchoring: output is an absolute path independent of CWD
# ============================================================================

@test "subdirectory CWD: output path is absolute, independent of CWD" {
  mkdir -p subdir
  cd subdir
  run_target_path --type notes --description "from subdir"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/notes/$STAMP-from-subdir.txt" ]
  [ -d "$TEST_TEMP_DIR/.claude-work/notes" ]
  [ ! -d "$TEST_TEMP_DIR/subdir/.claude-work" ]
}

# ============================================================================
# Configured segment: the work-item folder honors a non-default segment
# ============================================================================

@test "non-default segment config → folder under the configured segment" {
  local cfg="$TEST_TEMP_DIR/nondefault.json"
  printf '%s' '{"segment":"work"}' > "$cfg"
  git checkout -q -b issues/42
  run env PATH="$STUB_BIN:$PATH" MY_CLAUDE_SKILLS_CONFIG="$cfg" "$SCRIPT" --type scratchpads --description "Tracked elsewhere"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/work/42/scratchpads/$STAMP-tracked-elsewhere.txt" ]
}

@test "empty segment config → no segment directory under the identifier" {
  local cfg="$TEST_TEMP_DIR/empty-segment.json"
  printf '%s' '{"segment":""}' > "$cfg"
  git checkout -q -b issues/42
  run env PATH="$STUB_BIN:$PATH" MY_CLAUDE_SKILLS_CONFIG="$cfg" "$SCRIPT" --type questions --description "Flat layout"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/42/questions/$STAMP-flat-layout.txt" ]
}
