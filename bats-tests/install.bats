#!/usr/bin/env bats
#
# Tests for install.sh symlink handling. bats-tests/install-deps.bats only
# greps this script for its documented dependency lines, so these are its
# first behavioral tests. Each test runs against a fake repo and a fake HOME
# so nothing touches the developer's real ~/.claude/skills.
#
# Two behaviors are covered, both added by issues/261:
#   - a dangling link for a skill that still exists is reclaimed, not fatal
#   - a dangling link for a skill the repo dropped is pruned, but only when it
#     points into this checkout

load test_helper

SCRIPT="$PROJECT_ROOT/install.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  FAKE_HOME="$TEST_TEMP_DIR/home"
  FAKE_REPO="$TEST_TEMP_DIR/repo"
  mkdir -p "$FAKE_HOME/.claude/skills" "$FAKE_REPO/skills/alpha" "$FAKE_REPO/skills/beta"
  printf -- '---\nname: alpha\n---\n' > "$FAKE_REPO/skills/alpha/SKILL.md"
  printf -- '---\nname: beta\n---\n' > "$FAKE_REPO/skills/beta/SKILL.md"
  cp "$SCRIPT" "$FAKE_REPO/install.sh"
  # install.sh resolves REPO_DIR from git-common-dir when it is inside a repo,
  # so make the fake repo a real one and run from its root.
  git -C "$FAKE_REPO" init -q
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

run_install() {
  run env HOME="$FAKE_HOME" bash -c "cd '$FAKE_REPO' && ./install.sh"
}

# ============================================================================
# Baseline: a clean install links every skill
# ============================================================================

@test "clean install links every skill directory" {
  run_install
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.claude/skills/alpha" ]
  [ -L "$FAKE_HOME/.claude/skills/beta" ]
  [ "$(readlink "$FAKE_HOME/.claude/skills/alpha")" = "$FAKE_REPO/skills/alpha" ]
}

@test "rerunning reports the existing links as unchanged" {
  run_install
  run_install
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 unchanged"* ]]
}

# ============================================================================
# Dangling link for a skill that still exists: reclaimed, not fatal.
#
# Regression: `[ -e "$target" ]` is false for a dangling symlink, so control
# used to reach `ln -s`, which failed with "File exists"; set -euo pipefail
# then aborted the whole install. A link left over from a previous checkout
# path is exactly this case.
# ============================================================================

@test "dangling link to a previous checkout path is relinked, install succeeds" {
  ln -s "/nonexistent/old-checkout/skills/alpha" "$FAKE_HOME/.claude/skills/alpha"
  run_install
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.claude/skills/alpha" ]
  [ -e "$FAKE_HOME/.claude/skills/alpha" ]
  [ "$(readlink "$FAKE_HOME/.claude/skills/alpha")" = "$FAKE_REPO/skills/alpha" ]
  [[ "$output" == *"relinked"* ]]
  # Ownership of a dangling link is unknowable, so the reclaim names what it
  # discarded and the user can put it back.
  [[ "$output" == *"/nonexistent/old-checkout/skills/alpha"* ]]
}

@test "dangling link does not abort before later skills are linked" {
  ln -s "/nonexistent/old-checkout/skills/alpha" "$FAKE_HOME/.claude/skills/alpha"
  run_install
  [ "$status" -eq 0 ]
  # beta sorts after alpha, so it only gets linked if alpha did not abort.
  [ -e "$FAKE_HOME/.claude/skills/beta" ]
}

# ============================================================================
# Pruning links for skills the repo no longer ships
# ============================================================================

@test "dangling link into this checkout is pruned when the skill is gone" {
  ln -s "$FAKE_REPO/skills/removed" "$FAKE_HOME/.claude/skills/removed"
  run_install
  [ "$status" -eq 0 ]
  [ ! -L "$FAKE_HOME/.claude/skills/removed" ]
  [[ "$output" == *"pruned"* ]]
  [[ "$output" == *"1 pruned"* ]]
}

@test "dangling link pointing outside this checkout is left alone" {
  ln -s "/somewhere/else/skills/foreign" "$FAKE_HOME/.claude/skills/foreign"
  run_install
  [ "$status" -eq 0 ]
  # Equally broken, but not ours to remove.
  [ -L "$FAKE_HOME/.claude/skills/foreign" ]
  [[ "$output" == *"0 pruned"* ]]
}

@test "broken link whose target escapes through .. is left alone" {
  # Lexically under REPO_DIR, but it resolves outside the checkout. A target
  # that still existed would not be a broken link, so it cannot be resolved;
  # the escape is rejected instead.
  ln -s "$FAKE_REPO/skills/../../outside/skills/escaped" "$FAKE_HOME/.claude/skills/escaped"
  run_install
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.claude/skills/escaped" ]
  [[ "$output" == *"0 pruned"* ]]
}

@test "live link into this checkout is never pruned" {
  run_install
  run_install
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.claude/skills/alpha" ]
  [ -e "$FAKE_HOME/.claude/skills/alpha" ]
  [[ "$output" == *"0 pruned"* ]]
}

@test "real directory under skills/ is not treated as a prunable link" {
  mkdir -p "$FAKE_HOME/.claude/skills/handwritten"
  printf -- '---\nname: handwritten\n---\n' > "$FAKE_HOME/.claude/skills/handwritten/SKILL.md"
  run_install
  [ "$status" -eq 0 ]
  [ -d "$FAKE_HOME/.claude/skills/handwritten" ]
  [ -f "$FAKE_HOME/.claude/skills/handwritten/SKILL.md" ]
  [[ "$output" == *"0 pruned"* ]]
}

# ============================================================================
# An occupied target for a skill the repo DOES ship. The existing conflict
# test uses a name the fake repo does not ship, so the install loop never
# iterates over it and this block is never reached.
# ============================================================================

@test "live link pointing elsewhere is replaced and counted as updated" {
  mkdir -p "$TEST_TEMP_DIR/elsewhere/alpha"
  ln -s "$TEST_TEMP_DIR/elsewhere/alpha" "$FAKE_HOME/.claude/skills/alpha"
  run_install
  [ "$status" -eq 0 ]
  [ "$(readlink "$FAKE_HOME/.claude/skills/alpha")" = "$FAKE_REPO/skills/alpha" ]
  [[ "$output" == *"1 updated"* ]]
}

@test "regular file occupying a shipped skill name is left alone and flagged" {
  printf 'hand written\n' > "$FAKE_HOME/.claude/skills/alpha"
  run_install
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.claude/skills/alpha" ]
  [ ! -L "$FAKE_HOME/.claude/skills/alpha" ]
  [[ "$output" == *"WARNING"* ]]
  [[ "$output" == *"regular file"* ]]
  [[ "$output" == *"1 conflict"* ]]
  # The conflict must not stop the rest of the run.
  [ -L "$FAKE_HOME/.claude/skills/beta" ]
}

@test "real directory occupying a shipped skill name is left alone and flagged" {
  mkdir -p "$FAKE_HOME/.claude/skills/alpha"
  printf -- '---\nname: mine\n---\n' > "$FAKE_HOME/.claude/skills/alpha/SKILL.md"
  run_install
  [ "$status" -eq 0 ]
  [ -d "$FAKE_HOME/.claude/skills/alpha" ]
  [ -f "$FAKE_HOME/.claude/skills/alpha/SKILL.md" ]
  [[ "$output" == *"real directory"* ]]
  [[ "$output" == *"1 conflict"* ]]
  [ -L "$FAKE_HOME/.claude/skills/beta" ]
}
