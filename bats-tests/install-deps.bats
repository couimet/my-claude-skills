#!/usr/bin/env bats

load test_helper

# =============================================================
# External skill dependencies
# The repo's skills optionally call /asd-ste100 (danyuchn/asd-ste100-skill)
# and /grilling (mattpocock/skills). The install docs (README, install.sh)
# must list both so users installing via any path know what to install
# for full leverage. Both are optional: the suite degrades gracefully.
# =============================================================

README="$PROJECT_ROOT/README.md"
INSTALL_SH="$PROJECT_ROOT/install.sh"

@test "install-deps: install.sh lists the asd-ste100 dependency with its install command" {
  grep -q "npx skills add danyuchn/asd-ste100-skill --global" "$INSTALL_SH"
}

@test "install-deps: install.sh lists the grilling dependency with its install command" {
  grep -q "npx skills add mattpocock/skills --global" "$INSTALL_SH"
}

@test "install-deps: README Installation mentions /asd-ste100" {
  grep -q "/asd-ste100" "$README"
}

@test "install-deps: README Installation mentions /grilling" {
  grep -q "/grilling" "$README"
}

@test "install-deps: README gives the asd-ste100 install command" {
  grep -q "npx skills add danyuchn/asd-ste100-skill --global" "$README"
}

@test "install-deps: README gives the grilling install command" {
  grep -q "npx skills add mattpocock/skills --global" "$README"
}

# =============================================================
# Runtime command dependencies
# The work-item path resolver (issue-context scripts) shells out to jq at
# runtime. That is a command dependency, not a skill dependency, so it is
# declared in its own group rather than under the external-skills heading.
# Both docs must name the same install command exactly once, mirroring how the
# skill dependencies above are asserted.
# =============================================================

@test "install-deps: install.sh lists the jq command dependency exactly once" {
  [ "$(grep -c 'brew install jq' "$INSTALL_SH")" -eq 1 ]
}

@test "install-deps: README lists the jq command dependency exactly once" {
  [ "$(grep -c 'brew install jq' "$README")" -eq 1 ]
}
