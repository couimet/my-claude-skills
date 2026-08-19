#!/usr/bin/env bats

load test_helper

# =============================================================
# Transitive permission coverage, enforced by
# scripts/check-transitive-tools.sh. The validator compares each
# composite skill's declared allowed-tools with the full
# allowed-tools of each skill it invokes (see the INVOKES manifest
# in the script) and reports missing permissions.
# =============================================================

# =============================================================
# Repo gate: base mode must pass against the real skills/ tree.
# =============================================================

@test "transitive-tools: repo gate passes in base mode" {
  run "$PROJECT_ROOT/scripts/check-transitive-tools.sh" "$PROJECT_ROOT/skills"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================
# Base mode fixtures.
#
# The invocation manifest is keyed to the real skill names, so
# fixtures create all manifest skills with minimal front matter
# (name + allowed-tools only) and vary only the pair under test.
# =============================================================

MANIFEST_SKILLS="start-issue note scratchpad question cleanup-issue start-side-quest finish-issue tackle-pr-comment commit-msg tackle-scratchpad-block create-github-issue label-discovery"

# create_manifest_skills <root> <allowed-tools>
# Creates a minimal SKILL.md for every manifest skill under <root>.
create_manifest_skills() {
  local root="$1" tools="$2" name
  for name in $MANIFEST_SKILLS; do
    mkdir -p "$root/$name"
    printf -- '---\nname: %s\nallowed-tools: %s\n---\n' "$name" "$tools" > "$root/$name/SKILL.md"
  done
}

@test "transitive-tools: base mode detects a missing transitive permission" {
  local root="$TEST_TEMP_DIR/skills"
  mkdir -p "$root"
  create_manifest_skills "$root" "Read"
  # /note needs Bash(date *), which the /start-issue fixture lacks.
  printf -- '---\nname: note\nallowed-tools: Read, Bash(date *)\n---\n' > "$root/note/SKILL.md"

  run "$PROJECT_ROOT/scripts/check-transitive-tools.sh" "$root"

  [ "$status" -eq 1 ]
  [[ "$output" == *"missing Bash(date *)"* ]]
}

@test "transitive-tools: base mode passes when permissions are covered" {
  local root="$TEST_TEMP_DIR/skills"
  # A superset of /note's needs, declared by every fixture skill so all
  # manifest pairs are covered.
  local tools="Read, Glob, Write, Bash(mkdir -p *), Bash(date *), Bash(git branch --show-current), Bash(*/skills/issue-context/claude-work-root.sh *)"
  mkdir -p "$root"
  create_manifest_skills "$root" "$tools"

  run "$PROJECT_ROOT/scripts/check-transitive-tools.sh" "$root"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================
# Diff mode fixtures: a temp git repo whose history introduces a
# new /note invocation in /start-issue without the permission it
# requires.
# =============================================================

@test "transitive-tools: diff mode detects a new invocation" {
  local repo="$TEST_TEMP_DIR/repo"
  mkdir -p "$repo/skills/start-issue" "$repo/skills/note"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Bats Tester"
  printf -- '---\nname: start-issue\nallowed-tools: Read\n---\n' > "$repo/skills/start-issue/SKILL.md"
  printf -- '---\nname: note\nallowed-tools: Read, Bash(date *)\n---\n' > "$repo/skills/note/SKILL.md"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "baseline"
  printf -- 'Use /note with description x.\n' >> "$repo/skills/start-issue/SKILL.md"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "add-invocation"

  run "$PROJECT_ROOT/scripts/check-transitive-tools.sh" --diff HEAD~1..HEAD "$repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"missing Bash(date *)"* ]]
}

@test "transitive-tools: diff mode is clean without new invocations" {
  local repo="$TEST_TEMP_DIR/repo"
  mkdir -p "$repo/skills/start-issue" "$repo/skills/note"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Bats Tester"
  printf -- '---\nname: start-issue\nallowed-tools: Read\n---\n' > "$repo/skills/start-issue/SKILL.md"
  printf -- '---\nname: note\nallowed-tools: Read, Bash(date *)\n---\n' > "$repo/skills/note/SKILL.md"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "baseline"

  run "$PROJECT_ROOT/scripts/check-transitive-tools.sh" --diff HEAD..HEAD "$repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"no new gaps"* ]]
}
