#!/usr/bin/env bats

load test_helper

# =============================================================
# Direct permission coverage, enforced by
# scripts/check-direct-tools.sh. Every skill must declare, in its
# own allowed-tools, each repo script it tells the reader to run.
#
# check-transitive-tools.sh audits the other half of the rule,
# skill-to-skill coverage, and never looks at a skill's own script
# calls. A skill that gains a call and not the permission passes
# every other gate and then stops at a permission prompt in front
# of a user, which is how skills/issue-context/SKILL.md came to
# document work-folder-tier.sh without declaring it.
# =============================================================

SCRIPT="$PROJECT_ROOT/scripts/check-direct-tools.sh"

# Build a skills tree holding one skill.
# fixture <name> <allowed-tools line or ""> <body>
fixture() {
  local root="$TEST_TEMP_DIR/skills/$1"
  mkdir -p "$root"
  {
    echo "---"
    echo "name: $1"
    [ -z "$2" ] || echo "allowed-tools: $2"
    echo "---"
    echo ""
    printf '%s\n' "$3"
  } > "$root/SKILL.md"
}

# =============================================================
# Repo gate: must pass against the real skills/ tree.
# =============================================================

@test "direct-tools: repo gate passes" {
  run "$SCRIPT" "$PROJECT_ROOT/skills"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================
# A fenced call is an invocation
# =============================================================

@test "a fenced call with no matching permission is a gap" {
  fixture caller "Read" '```bash
~/.claude/skills/issue-context/target-path.sh --type notes
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"target-path.sh"* ]]
  [[ "$output" == *"does not declare it"* ]]
}

@test "a fenced call with the matching permission passes" {
  fixture caller 'Read, Bash(*/skills/issue-context/target-path.sh *)' '```bash
~/.claude/skills/issue-context/target-path.sh --type notes
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a skill with no allowed-tools at all is a gap when it calls something" {
  fixture caller "" '```bash
~/.claude/skills/issue-context/target-path.sh --type notes
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 1 ]
}

@test "every missing script is reported, not just the first" {
  fixture caller "Read" '```bash
~/.claude/skills/issue-context/target-path.sh --type notes
~/.claude/skills/issue-context/branch-issue-id.sh
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "the same script called twice is reported once" {
  fixture caller "Read" '```bash
~/.claude/skills/issue-context/target-path.sh --type notes
~/.claude/skills/issue-context/target-path.sh --type questions
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "${#lines[@]}" -eq 1 ]
}

# =============================================================
# A prose mention is description
# =============================================================

@test "a script named in prose without a fence is not a call" {
  # /file-placement says which skills delegate their filenames to
  # target-path.sh without ever running it. A rule that could not tell
  # that apart would push a permission onto a skill with no use for one.
  fixture caller "Read" 'The note skills delegate to `~/.claude/skills/issue-context/target-path.sh` for the filename.'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a fenced call counts even when the same script is also named in prose" {
  fixture caller "Read" 'Resolve it with `~/.claude/skills/issue-context/target-path.sh`:

```bash
~/.claude/skills/issue-context/target-path.sh --type notes
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 1 ]
}

# =============================================================
# A declaration is read across its continuation lines
# =============================================================

# raw_fixture <name> <full SKILL.md text> — for the cases where the
# declaration's exact line shape is the thing under test.
raw_fixture() {
  local root="$TEST_TEMP_DIR/skills/$1"
  mkdir -p "$root"
  printf '%s\n' "$2" > "$root/SKILL.md"
}

@test "a declaration wrapped onto a continuation line still counts" {
  # YAML lets the value wrap, and check-transitive-tools.sh reads it that
  # way. A checker keeping only the key line would call this a gap.
  raw_fixture caller '---
name: caller
allowed-tools: Read,
  Bash(*/skills/issue-context/target-path.sh *)
---

```bash
~/.claude/skills/issue-context/target-path.sh --type notes
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a continuation line is still a gap when it declares something else" {
  raw_fixture caller '---
name: caller
allowed-tools: Read,
  Bash(*/skills/issue-context/branch-issue-id.sh *)
---

```bash
~/.claude/skills/issue-context/target-path.sh --type notes
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"target-path.sh"* ]]
}

@test "a later front matter key is not read as part of the declaration" {
  raw_fixture caller '---
name: caller
allowed-tools: Read
argument-hint: pass it to */skills/issue-context/target-path.sh *
---

```bash
~/.claude/skills/issue-context/target-path.sh --type notes
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 1 ]
}

# =============================================================
# A declaration is matched by the whole called path
# =============================================================

@test "a permission naming another skill's script of the same name is a gap" {
  # Matching the bare filename would accept this, and the skill would then
  # stop at a permission prompt in front of a user anyway.
  fixture caller 'Read, Bash(*/skills/other-skill/target-path.sh *)' '```bash
~/.claude/skills/issue-context/target-path.sh --type notes
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/issue-context/target-path.sh"* ]]
}

@test "a permission for a near-miss filename is a gap" {
  # Searching the declaration for the call as a substring accepts this: the
  # declared path contains the called one. The permission would not fire at
  # runtime, so the gate has to say so.
  fixture caller 'Read, Bash(*/skills/issue-context/target-path.sh.bak *)' '```bash
~/.claude/skills/issue-context/target-path.sh --type notes
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/issue-context/target-path.sh"* ]]
}

@test "a permission whose path only ends on the called one is a gap" {
  # The call's whole path must be preceded by a slash, or "myskills/..." would
  # cover "skills/...".
  fixture caller 'Read, Bash(*/myskills/issue-context/target-path.sh *)' '```bash
~/.claude/skills/issue-context/target-path.sh --type notes
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/issue-context/target-path.sh"* ]]
}

@test "a permission declaring the call with no glob prefix passes" {
  fixture caller 'Read, Bash(skills/issue-context/target-path.sh *)' '```bash
~/.claude/skills/issue-context/target-path.sh --type notes
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================
# Bash(*) is the one wildcard
# =============================================================

@test "Bash(*) satisfies every call" {
  fixture caller 'Read, Bash(*)' '```bash
~/.claude/skills/issue-context/target-path.sh --type notes
```'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 0 ]
}

# =============================================================
# Shape
# =============================================================

@test "a skill calling nothing passes whatever it declares" {
  fixture caller "Read" 'No scripts here.'
  run "$SCRIPT" "$TEST_TEMP_DIR/skills"
  [ "$status" -eq 0 ]
}

@test "a missing skills root errors" {
  run "$SCRIPT" "$TEST_TEMP_DIR/not-there"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills root not found"* ]]
}
