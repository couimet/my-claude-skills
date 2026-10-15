#!/usr/bin/env bats
#
# Tests for skills/issue-context/topic-root.sh — the one definition of the
# directory a topic slug resolves under. The helper is sourced, not executed,
# so every test sources it with issue-settings.sh inside a clean subshell and
# asserts on the root and the reason it hands back.
#
# Every run points MY_CLAUDE_SKILLS_CONFIG at a temp settings file, so a
# developer's own launchAgentDefaultFolder never moves a result.

load test_helper

HELPERS="$PROJECT_ROOT/skills/issue-context"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  # pwd -P: macOS hands out /var/... temp paths that resolve under /private.
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  export MY_CLAUDE_SKILLS_CONFIG="$TEST_TEMP_DIR/settings.json"
  REPO="$TEST_TEMP_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
}

# topic_root <dir> — source the helpers in <dir> and print "<rc> <root>
# <reason>".
topic_root() {
  run bash -c 'cd "$1" && source "$2/issue-settings.sh" 2>/dev/null && source "$2/topic-root.sh"
    root="unset" reason="unset"
    _issue_context_topic_root root reason && rc=0 || rc=$?
    printf "%s|%s|%s\n" "$rc" "$root" "$reason"' _ "$1" "$HELPERS"
}

@test "no setting: the root of the current repository" {
  topic_root "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "0|$REPO|" ]
}

@test "no setting, from a subdirectory: still the repository root" {
  mkdir -p "$REPO/a/b"
  topic_root "$REPO/a/b"
  [ "$output" = "0|$REPO|" ]
}

@test "the setting wins over the repository root, trailing slashes removed" {
  mkdir -p "$TEST_TEMP_DIR/topics"
  printf '{"launchAgentDefaultFolder": "%s//"}\n' "$TEST_TEMP_DIR/topics" > "$MY_CLAUDE_SKILLS_CONFIG"
  topic_root "$REPO"
  [ "$output" = "0|$TEST_TEMP_DIR/topics|" ]
}

@test "the setting works outside any repository" {
  mkdir -p "$TEST_TEMP_DIR/topics" "$TEST_TEMP_DIR/plain"
  printf '{"launchAgentDefaultFolder": "%s"}\n' "$TEST_TEMP_DIR/topics" > "$MY_CLAUDE_SKILLS_CONFIG"
  topic_root "$TEST_TEMP_DIR/plain"
  [ "$output" = "0|$TEST_TEMP_DIR/topics|" ]
}

@test "a relative setting → reason relative, no root" {
  printf '{"launchAgentDefaultFolder": "topics"}\n' > "$MY_CLAUDE_SKILLS_CONFIG"
  topic_root "$REPO"
  [ "$output" = "1||relative" ]
}

@test "a setting naming no directory → reason missing, no root" {
  printf '{"launchAgentDefaultFolder": "%s"}\n' "$TEST_TEMP_DIR/nowhere" > "$MY_CLAUDE_SKILLS_CONFIG"
  topic_root "$REPO"
  [ "$output" = "1||missing" ]
}

@test "a settings file that cannot be read → reason settings, no fall-back" {
  printf '{ not json\n' > "$MY_CLAUDE_SKILLS_CONFIG"
  topic_root "$REPO"
  [ "$output" = "1||settings" ]
}

@test "no setting and no repository → reason norepo" {
  mkdir -p "$TEST_TEMP_DIR/plain"
  topic_root "$TEST_TEMP_DIR/plain"
  [ "$output" = "1||norepo" ]
}
