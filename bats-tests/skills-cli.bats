#!/usr/bin/env bats

load test_helper

# =============================================================
# The skills CLI (skills.sh, `npx skills add <repo> --global`) is the cross-agent installer behind the README quick-install path.
# These tests prove the CLI can discover and install this repo's skill suite with companion scripts intact.
# The CLI version is pinned so CI and local runs stay deterministic.
# =============================================================

SKILLS_CLI_VERSION=1.5.23
SKILLS_CLI="npx --yes skills@${SKILLS_CLI_VERSION}"

@test "skills-cli: discovery lists every skill directory in skills/" {
  expected="$(find "$PROJECT_ROOT/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)"

  run $SKILLS_CLI add "$PROJECT_ROOT" --list

  [ "$status" -eq 0 ]
  # The CLI colors skill names with ANSI escapes when CI=true; strip them so
  # the "$" anchor matches the name regardless of terminal styling.
  plain_output="$(printf '%s\n' "$output" | sed "s/$(printf '\033')\[[0-9;?]*[a-zA-Z]//g")"
  for name in $expected; do
    printf '%s\n' "$plain_output" | grep -qE "${name}$" || {
      echo "Skill not discovered by skills CLI: $name"
      return 1
    }
  done
}

@test "skills-cli: global install copies every skill with companion scripts" {
  export HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$HOME"

  run $SKILLS_CLI add "$PROJECT_ROOT" --global --agent claude-code --skill '*' --yes

  [ "$status" -eq 0 ]
  installed="$HOME/.claude/skills"
  while IFS= read -r dir; do
    name="$(basename "$dir")"
    [ -f "$installed/$name/SKILL.md" ] || {
      echo "Installed skill missing: $name"
      return 1
    }
  done < <(find "$PROJECT_ROOT/skills" -mindepth 1 -maxdepth 1 -type d)

  # Script-backed skills keep their helper scripts, executable.
  [ -x "$installed/issue-context/claude-work-root.sh" ]
  [ -x "$installed/auto-number/auto-number.sh" ]
  [ -x "$installed/cleanup-issue/remove-issue-dir.sh" ]
  [ -x "$installed/rebase-issue/apply-stacked-diff.sh" ]
}
