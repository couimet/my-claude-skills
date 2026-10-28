#!/usr/bin/env bats
#
# Tests for install.sh symlink handling. bats-tests/install-deps.bats only
# greps this script for its documented dependency lines, so these are its
# first behavioral tests. Each test runs against a fake repo and a fake HOME
# so nothing touches the developer's real ~/.claude/skills.
#
# Two behaviors are covered, both added by issues/261:
#   - a dangling link for a skill that still exists is reclaimed, not fatal
#   - a dangling link for a skill the repo dropped is pruned, but only when its
#     stored target has the exact shape install.sh writes, REPO_DIR/<one
#     component>, which is what makes it attributable to this checkout

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
  # The hook step checks that the script of the entry can run, so the fake
  # repo ships a stub of it.
  mkdir -p "$FAKE_REPO/skills/issue-context"
  printf '#!/bin/sh\nexit 0\n' > "$FAKE_REPO/skills/issue-context/session-hook.sh"
  chmod +x "$FAKE_REPO/skills/issue-context/session-hook.sh"
  cp "$SCRIPT" "$FAKE_REPO/install.sh"
  # install.sh resolves REPO_DIR from git-common-dir when it is inside a repo,
  # so make the fake repo a real one and run from its root.
  git -C "$FAKE_REPO" init -q
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# run_install [args...] — run install.sh from the fake repo with the fake
# HOME. ANSWER is the text on its standard input, the answer to the hook
# question; with no ANSWER, standard input is empty, which answers no.
run_install() {
  run env HOME="$FAKE_HOME" bash -c 'cd "$1" && shift && exec ./install.sh "$@"' _ "$FAKE_REPO" "$@" \
    < <(printf '%s' "${ANSWER-}")
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
  [[ "$output" == *"3 unchanged"* ]] || false
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
  [[ "$output" == *"relinked"* ]] || false
  # Ownership of a dangling link is unknowable, so the reclaim names what it
  # discarded and the user can put it back.
  [[ "$output" == *"/nonexistent/old-checkout/skills/alpha"* ]] || false
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
  [[ "$output" == *"pruned"* ]] || false
  [[ "$output" == *"1 pruned"* ]] || false
}

@test "dangling link pointing outside this checkout is left alone" {
  ln -s "/somewhere/else/skills/foreign" "$FAKE_HOME/.claude/skills/foreign"
  run_install
  [ "$status" -eq 0 ]
  # Equally broken, but not ours to remove.
  [ -L "$FAKE_HOME/.claude/skills/foreign" ]
  [[ "$output" == *"0 pruned"* ]] || false
}

@test "broken link whose target escapes through .. is left alone" {
  # Lexically under REPO_DIR, but it resolves outside the checkout. install.sh
  # only ever writes REPO_DIR/<one component>, so this shape was not created by
  # it and is not attributable to this checkout, whatever it resolves to.
  ln -s "$FAKE_REPO/skills/../../outside/skills/escaped" "$FAKE_HOME/.claude/skills/escaped"
  run_install
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.claude/skills/escaped" ]
  [[ "$output" == *"0 pruned"* ]] || false
}

@test "broken link reaching outside through a symlink component is left alone" {
  # A lexical REPO_DIR/* prefix test passed this: the prefix is present and no
  # `..` appears, yet `outbound` redirects the whole path out of the checkout.
  # Requiring REPO_DIR/<one component> rejects it without resolving anything.
  mkdir -p "$TEST_TEMP_DIR/outside"
  ln -s "$TEST_TEMP_DIR/outside" "$FAKE_REPO/skills/outbound"
  ln -s "$FAKE_REPO/skills/outbound/removed" "$FAKE_HOME/.claude/skills/removed"
  run_install
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.claude/skills/removed" ]
  [[ "$output" == *"0 pruned"* ]] || false
}

@test "live link into this checkout is never pruned" {
  run_install
  run_install
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.claude/skills/alpha" ]
  [ -e "$FAKE_HOME/.claude/skills/alpha" ]
  [[ "$output" == *"0 pruned"* ]] || false
}

@test "real directory under skills/ is not treated as a prunable link" {
  mkdir -p "$FAKE_HOME/.claude/skills/handwritten"
  printf -- '---\nname: handwritten\n---\n' > "$FAKE_HOME/.claude/skills/handwritten/SKILL.md"
  run_install
  [ "$status" -eq 0 ]
  [ -d "$FAKE_HOME/.claude/skills/handwritten" ]
  [ -f "$FAKE_HOME/.claude/skills/handwritten/SKILL.md" ]
  [[ "$output" == *"0 pruned"* ]] || false
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
  [[ "$output" == *"1 updated"* ]] || false
}

@test "regular file occupying a shipped skill name is left alone and flagged" {
  printf 'hand written\n' > "$FAKE_HOME/.claude/skills/alpha"
  run_install
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.claude/skills/alpha" ]
  [ ! -L "$FAKE_HOME/.claude/skills/alpha" ]
  [[ "$output" == *"WARNING"* ]] || false
  [[ "$output" == *"regular file"* ]] || false
  [[ "$output" == *"1 conflict"* ]] || false
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
  [[ "$output" == *"real directory"* ]] || false
  [[ "$output" == *"1 conflict"* ]] || false
  [ -L "$FAKE_HOME/.claude/skills/beta" ]
}

# ============================================================================
# The Claude Code hook step (issue 296). Every test edits a settings file
# under the fake HOME, never the developer's own.
# ============================================================================

SETTINGS_REL=".claude/settings.json"
HOOK_SUFFIX="/issue-context/session-hook.sh"

# hook_count <event> — count the entries of this hook under <event>.
hook_count() {
  jq --arg e "$1" --arg s "$HOOK_SUFFIX" \
    '[.hooks[$e][]?.hooks[]? | select(.command | endswith($s))] | length' "$FAKE_HOME/$SETTINGS_REL"
}

@test "hook: a yes adds one entry for each event, with the matchers and the absolute command" {
  ANSWER=y run_install
  [ "$status" -eq 0 ]
  [ "$(hook_count SessionStart)" -eq 1 ]
  [ "$(hook_count SessionEnd)" -eq 1 ]
  [ "$(hook_count UserPromptSubmit)" -eq 1 ]
  [ "$(jq -r '.hooks.SessionStart[0].matcher' "$FAKE_HOME/$SETTINGS_REL")" = "clear|resume" ]
  [ "$(jq -r '.hooks.SessionEnd[0].matcher' "$FAKE_HOME/$SETTINGS_REL")" = "clear" ]
  [ "$(jq -r '.hooks.UserPromptSubmit[0] | has("matcher")' "$FAKE_HOME/$SETTINGS_REL")" = "false" ]
  [ "$(jq -r '.hooks.SessionEnd[0].hooks[0].command' "$FAKE_HOME/$SETTINGS_REL")" = "$FAKE_HOME/.claude/skills/issue-context/session-hook.sh" ]
  [[ "$output" == *"[y/N]"* ]] || false
  [[ "$output" == *"Claude Code hook: added"* ]] || false
}

@test "hook: the edit keeps every other key and hook, and writes a backup first" {
  printf '%s' '{"model":"x","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/other/hook.sh"}]}],"Stop":[{"hooks":[{"type":"command","command":"/stop.sh"}]}]}}' \
    > "$FAKE_HOME/$SETTINGS_REL"
  cp "$FAKE_HOME/$SETTINGS_REL" "$TEST_TEMP_DIR/before.json"
  ANSWER=y run_install
  [ "$status" -eq 0 ]
  [ "$(jq -r .model "$FAKE_HOME/$SETTINGS_REL")" = "x" ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$FAKE_HOME/$SETTINGS_REL")" = "/stop.sh" ]
  [ "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$FAKE_HOME/$SETTINGS_REL")" = "/other/hook.sh" ]
  [ "$(hook_count SessionStart)" -eq 1 ]
  local backup
  backup="$(ls "$FAKE_HOME/.claude/"settings.json.bak-*)"
  cmp -s "$backup" "$TEST_TEMP_DIR/before.json"
}

@test "hook: a second run adds nothing and asks nothing" {
  ANSWER=y run_install
  ANSWER=y run_install
  [ "$status" -eq 0 ]
  [ "$(hook_count SessionStart)" -eq 1 ]
  [ "$(hook_count SessionEnd)" -eq 1 ]
  [ "$(hook_count UserPromptSubmit)" -eq 1 ]
  [[ "$output" == *"Claude Code hook: already in"* ]] || false
  [[ "$output" != *"[y/N]"* ]] || false
}

@test "hook: an entry with only the two earlier events gets the UserPromptSubmit event" {
  local cmd="$FAKE_HOME/.claude/skills/issue-context/session-hook.sh"
  jq -n --arg cmd "$cmd" '{hooks: {
    SessionStart: [{matcher: "clear|resume", hooks: [{type: "command", command: $cmd}]}],
    SessionEnd: [{matcher: "clear", hooks: [{type: "command", command: $cmd}]}]}}' > "$FAKE_HOME/$SETTINGS_REL"
  ANSWER=y run_install
  [ "$status" -eq 0 ]
  [[ "$output" == *"Claude Code hook: added"* ]] || false
  [ "$(hook_count SessionStart)" -eq 1 ]
  [ "$(hook_count SessionEnd)" -eq 1 ]
  [ "$(hook_count UserPromptSubmit)" -eq 1 ]
}

@test "hook: an old entry of the hook is replaced, not doubled" {
  printf '%s' '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"~/.claude/skills/issue-context/session-hook.sh"}]}]}}' \
    > "$FAKE_HOME/$SETTINGS_REL"
  ANSWER=y run_install
  [ "$status" -eq 0 ]
  [ "$(hook_count SessionStart)" -eq 1 ]
  [ "$(jq '.hooks.SessionStart | length' "$FAKE_HOME/$SETTINGS_REL")" -eq 1 ]
}

@test "hook: a script that cannot run is not added, and nothing is asked" {
  rm "$FAKE_REPO/skills/issue-context/session-hook.sh"
  ANSWER=y run_install
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/$SETTINGS_REL" ]
  [[ "$output" == *"not added, because $FAKE_HOME/.claude/skills/issue-context/session-hook.sh cannot run"* ]] || false
  [[ "$output" == *"Update $FAKE_REPO so it has the script"* ]] || false
  [[ "$output" != *"[y/N]"* ]] || false
}

@test "hook: an entry whose script cannot run is reported, not passed as already in" {
  ANSWER=y run_install
  cp "$FAKE_HOME/$SETTINGS_REL" "$TEST_TEMP_DIR/before.json"
  chmod -x "$FAKE_REPO/skills/issue-context/session-hook.sh"
  ANSWER=y run_install
  [ "$status" -eq 0 ]
  cmp -s "$FAKE_HOME/$SETTINGS_REL" "$TEST_TEMP_DIR/before.json"
  [[ "$output" == *"cannot run"* ]] || false
  [[ "$output" == *"install.sh --uninstall-hooks"* ]] || false
  [[ "$output" != *"already in"* ]] || false
}

@test "hook: no answer changes nothing and prints the entry to add by hand" {
  run_install
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/$SETTINGS_REL" ]
  [[ "$output" == *"Claude Code hook: not added"* ]] || false
  [[ "$output" == *"\"matcher\": \"clear|resume\""* ]] || false
}

@test "hook: a no changes nothing" {
  printf '%s' '{"model":"x"}' > "$FAKE_HOME/$SETTINGS_REL"
  ANSWER=n run_install
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_HOME/$SETTINGS_REL")" = '{"model":"x"}' ]
  ! ls "$FAKE_HOME/.claude/"settings.json.bak-* 2>/dev/null
}

@test "hook: --no-hooks links the skills, and asks nothing" {
  ANSWER=y run_install --no-hooks
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/.claude/skills/alpha" ]
  [ ! -e "$FAKE_HOME/$SETTINGS_REL" ]
  [[ "$output" == *"skipped (--no-hooks)"* ]] || false
  [[ "$output" != *"[y/N]"* ]] || false
}

@test "hook: a settings file that is not a JSON object is not changed" {
  printf 'not json' > "$FAKE_HOME/$SETTINGS_REL"
  ANSWER=y run_install
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_HOME/$SETTINGS_REL")" = "not json" ]
  [[ "$output" == *"is not a JSON object, so it was not changed"* ]] || false
}

@test "hook: a symlinked settings file is written through, and stays a link" {
  printf '%s' '{"model":"x"}' > "$TEST_TEMP_DIR/dotfiles-settings.json"
  ln -s "$TEST_TEMP_DIR/dotfiles-settings.json" "$FAKE_HOME/$SETTINGS_REL"
  ANSWER=y run_install
  [ "$status" -eq 0 ]
  [ -L "$FAKE_HOME/$SETTINGS_REL" ]
  [ "$(jq -r .model "$TEST_TEMP_DIR/dotfiles-settings.json")" = "x" ]
  [ "$(hook_count SessionEnd)" -eq 1 ]
}

@test "hook: --uninstall-hooks removes only the entries of the hook, and links nothing" {
  printf '%s' '{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/stop.sh"}]}]}}' \
    > "$FAKE_HOME/$SETTINGS_REL"
  ANSWER=y run_install
  rm -rf "$FAKE_HOME/.claude/skills"
  run_install --uninstall-hooks
  [ "$status" -eq 0 ]
  [ "$(hook_count SessionStart)" -eq 0 ]
  [ "$(hook_count SessionEnd)" -eq 0 ]
  [ "$(jq -r '.hooks | keys | join(",")' "$FAKE_HOME/$SETTINGS_REL")" = "Stop" ]
  [ "$(jq -r .model "$FAKE_HOME/$SETTINGS_REL")" = "x" ]
  [ ! -e "$FAKE_HOME/.claude/skills" ]
  [[ "$output" == *"Removed the hook entry"* ]] || false
}

@test "hook: --uninstall-hooks drops an empty hooks key" {
  ANSWER=y run_install
  run_install --uninstall-hooks
  [ "$status" -eq 0 ]
  [ "$(jq -c . "$FAKE_HOME/$SETTINGS_REL")" = "{}" ]
}

@test "hook: --uninstall-hooks with no entry changes nothing" {
  printf '%s' '{"model":"x"}' > "$FAKE_HOME/$SETTINGS_REL"
  run_install --uninstall-hooks
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_HOME/$SETTINGS_REL")" = '{"model":"x"}' ]
  [[ "$output" == *"nothing to remove"* ]] || false
}

@test "hook: an unknown argument fails with the usage" {
  run_install --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument '--bogus'"* ]] || false
}

@test "hook: the plugin hooks file and install.sh name the same script and matchers" {
  local hooks="$PROJECT_ROOT/hooks/hooks.json"
  [ "$(jq -r '.hooks.SessionStart[0].matcher' "$hooks")" = "clear|resume" ]
  [ "$(jq -r '.hooks.SessionEnd[0].matcher' "$hooks")" = "clear" ]
  [ "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$hooks")" = '${CLAUDE_PLUGIN_ROOT}/skills/issue-context/session-hook.sh' ]
  [ "$(jq -r '.hooks.SessionEnd[0].hooks[0].command' "$hooks")" = '${CLAUDE_PLUGIN_ROOT}/skills/issue-context/session-hook.sh' ]
  [ "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$hooks")" = '${CLAUDE_PLUGIN_ROOT}/skills/issue-context/session-hook.sh' ]
  [ "$(jq -r '.hooks.UserPromptSubmit[0] | has("matcher")' "$hooks")" = "false" ]
  grep -q 'HOOK_COMMAND="$SKILLS_DIR/issue-context/session-hook.sh"' "$SCRIPT"
}

@test "hook: the script that the hooks file names exists and is executable" {
  [ -x "$PROJECT_ROOT/skills/issue-context/session-hook.sh" ]
}

# ============================================================================
# A linked git worktree. A worktree is ephemeral, so install.sh links nothing
# from it, and names the main checkout to run it from.
# ============================================================================

# add_worktree — commit the fake repo, and add a linked worktree of it at
# $WORKTREE.
add_worktree() {
  WORKTREE="$TEST_TEMP_DIR/worktree"
  git -C "$FAKE_REPO" add -A
  git -C "$FAKE_REPO" -c user.name=t -c user.email=t@t commit -q -m init
  git -C "$FAKE_REPO" worktree add -q -b side "$WORKTREE"
}

# run_install_in <dir> [args...] — run_install, from <dir> instead of the fake
# repo.
run_install_in() {
  local dir="$1"
  shift
  run env HOME="$FAKE_HOME" bash -c 'cd "$1" && shift && exec ./install.sh "$@"' _ "$dir" "$@" \
    < <(printf '%s' "${ANSWER-}")
}

@test "worktree: install.sh from a linked worktree links nothing, and names the main checkout" {
  add_worktree
  ANSWER=y run_install_in "$WORKTREE"
  [ "$status" -eq 1 ]
  [ -z "$(ls -A "$FAKE_HOME/.claude/skills")" ]
  [ ! -e "$FAKE_HOME/$SETTINGS_REL" ]
  [[ "$output" == *"is a linked git worktree, so nothing was linked"* ]] || false
  [[ "$output" == *"Run install.sh from the main checkout: $FAKE_REPO/install.sh"* ]] || false
}

@test "worktree: --uninstall-hooks runs from a linked worktree" {
  ANSWER=y run_install
  add_worktree
  run_install_in "$WORKTREE" --uninstall-hooks
  [ "$status" -eq 0 ]
  [ "$(hook_count SessionStart)" -eq 0 ]
  [[ "$output" == *"Removed the hook entry"* ]] || false
}

@test "worktree: install.sh from the main checkout of a repo with worktrees links as usual" {
  add_worktree
  run_install
  [ "$status" -eq 0 ]
  [ "$(readlink "$FAKE_HOME/.claude/skills/alpha")" = "$FAKE_REPO/skills/alpha" ]
}
