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
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-001-plan-the-refactor.txt" ]
}

@test "issues/120-extract-numeric-prefix → extracts 120" {
  git checkout -q -b issues/120-audit-cleanup
  run_target_path --type questions --description "Scope question"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/120/questions/$STAMP-001-scope-question.txt" ]
}

@test "issues/120_with_underscore → extracts 120" {
  git checkout -q -b issues/120_audit
  run_target_path --type scratchpads --description "Test"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/120/scratchpads/$STAMP-001-test.txt" ]
}

@test "issues/rfc-auth → non-numeric prefix uses full segment" {
  git checkout -q -b issues/rfc-auth
  run_target_path --type commit-msgs --description "Draft message"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/rfc-auth/commit-msgs/$STAMP-001-draft-message.txt" ]
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
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/scratchpads/$STAMP-001-hello-world.txt" ]
}

@test "side-quest/foo branch → flat-root placement" {
  git checkout -q -b side-quest/foo
  run_target_path --type questions --description "Side quest question"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/questions/$STAMP-001-side-quest-question.txt" ]
}

# ============================================================================
# Same-second ordering. The ordinal between the stamp and the slug is what
# makes a byte-order sort of the directory equal creation order, and it is also
# what resolves a collision. The stubbed clock is what makes this reachable —
# two real calls would almost always land in different seconds.
# ============================================================================

@test "same second, same slug → next ordinal instead of overwrite" {
  git checkout -q -b issues/42
  run_target_path --type scratchpads --description "Plan"
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-001-plan.txt" ]
  run_target_path --type scratchpads --description "Plan"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-002-plan.txt" ]
}

@test "same second, same slug, twice over → 003 after 002 is taken" {
  git checkout -q -b issues/42
  run_target_path --type scratchpads --description "Plan"
  run_target_path --type scratchpads --description "Plan"
  run_target_path --type scratchpads --description "Plan"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-003-plan.txt" ]
}

@test "same second, different slug → ordinal still advances" {
  git checkout -q -b issues/42
  run_target_path --type scratchpads --description "First"
  run_target_path --type scratchpads --description "Second"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-002-second.txt" ]
}

@test "same second, different slugs → byte order equals creation order" {
  git checkout -q -b issues/42
  # z before a: the slug alone would sort these backwards.
  run_target_path --type scratchpads --description "zebra"
  local first="$output"
  run_target_path --type scratchpads --description "apple"
  local second="$output"
  [ "$status" -eq 0 ]
  # A plain sort of the directory must list them in the order they were made.
  run bash -c "ls '$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads' | sort"
  [ "${lines[0]}" = "$(basename "$first")" ]
  [ "${lines[1]}" = "$(basename "$second")" ]
}

# ============================================================================
# The path is reserved, not merely tested. The reservation is what closes the
# window in which two callers could be handed the same name, and it is what
# makes the ordinal scan above authoritative.
# ============================================================================

@test "returned path exists and is empty, ready for the caller to write" {
  git checkout -q -b issues/42
  run_target_path --type scratchpads --description "Reserved"
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  [ ! -s "$output" ]
}

@test "dangling symlink at the candidate path is skipped, not written through" {
  git checkout -q -b issues/42
  mkdir -p ".claude-work/issues/42/scratchpads"
  # -e is false for this, so a plain existence test would hand the path back
  # and the caller's write would follow the link out of the directory.
  ln -s "$TEST_TEMP_DIR/outside-the-work-dir.txt" \
    ".claude-work/issues/42/scratchpads/$STAMP-001-trap.txt"
  run_target_path --type scratchpads --description "Trap"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-002-trap.txt" ]
  [ ! -e "$TEST_TEMP_DIR/outside-the-work-dir.txt" ]
}

@test "exhausted ordinals for one second error with T103" {
  git checkout -q -b issues/42
  mkdir -p ".claude-work/issues/42/scratchpads"
  touch ".claude-work/issues/42/scratchpads/$STAMP-999-taken.txt"
  run_target_path --type scratchpads --description "One too many"
  [ "$status" -eq 1 ]
  [[ "$output" == *"T103"* ]]
}

# ============================================================================
# Regression, issues/261 Defect 1: the retired auto-number.sh read the leading
# digit run of a sibling as its high-water mark, so one date-named file
# permanently converted a directory's sequence to 8-digit pseudo-dates. The
# ordinal scan reads only names carrying this second's stamp and a three-digit
# field, so neither of these siblings is read at all.
# ============================================================================

@test "date-prefixed sibling does not influence the emitted name" {
  git checkout -q -b issues/42
  mkdir -p ".claude-work/issues/42/scratchpads"
  # The exact filename from the issue's reproduction case.
  touch ".claude-work/issues/42/scratchpads/20260902-131841-third.txt"
  run_target_path --type scratchpads --description "Unaffected"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-001-unaffected.txt" ]
}

@test "NNNN-prefixed leftovers from the retired scheme are ignored" {
  git checkout -q -b issues/42
  mkdir -p ".claude-work/issues/42/scratchpads"
  touch ".claude-work/issues/42/scratchpads/0001-first.txt"
  touch ".claude-work/issues/42/scratchpads/0002-second.txt"
  run_target_path --type scratchpads --description "Third"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-001-third.txt" ]
}

# ============================================================================
# Slug normalization
# ============================================================================

@test "slug lowercases, hyphenates, and collapses separators" {
  git checkout -q -b issues/42
  run_target_path --type scratchpads --description "Some   MIXED--Case & punctuation!"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-001-some-mixed-case-punctuation.txt" ]
}

@test "slug trims leading and trailing hyphens" {
  git checkout -q -b issues/42
  run_target_path --type scratchpads --description "  hello world  "
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/scratchpads/$STAMP-001-hello-world.txt" ]
}

# ============================================================================
# Extension override
# ============================================================================

@test "--ext overrides default txt extension" {
  git checkout -q -B main
  run_target_path --type scratchpads --description "Config" --ext json
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/scratchpads/$STAMP-001-config.json" ]
}

@test "--ext md still works alongside json" {
  git checkout -q -B main
  run_target_path --type scratchpads --description "Doc" --ext md
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/scratchpads/$STAMP-001-doc.md" ]
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
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/42/notes/$STAMP-001-plan-the-work.txt" ]
}

@test "notes type on main branch → flat-root notes path" {
  git checkout -q -B main
  run_target_path --type notes --description "Quick finding"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/notes/$STAMP-001-quick-finding.txt" ]
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
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/issues/99/notes/$STAMP-001-from-worktree.txt" ]
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
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/notes/$STAMP-001-from-subdir.txt" ]
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
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/work/42/scratchpads/$STAMP-001-tracked-elsewhere.txt" ]
}

@test "empty segment config → no segment directory under the identifier" {
  local cfg="$TEST_TEMP_DIR/empty-segment.json"
  printf '%s' '{"segment":""}' > "$cfg"
  git checkout -q -b issues/42
  run env PATH="$STUB_BIN:$PATH" MY_CLAUDE_SKILLS_CONFIG="$cfg" "$SCRIPT" --type questions --description "Flat layout"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TEMP_DIR/.claude-work/42/questions/$STAMP-001-flat-layout.txt" ]
}
