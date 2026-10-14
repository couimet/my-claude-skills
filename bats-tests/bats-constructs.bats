#!/usr/bin/env bats
#
# Enforces the `[[ ... ]] || false` form for each `[[ ]]` assertion in the
# suite.
#
# Under bash 3.2, the /bin/bash of macOS that Homebrew bats runs on, a failed
# `[[ ]]` that is not the last command of a test does not fail the test. CI
# runs bash 5, where it does, so a test can pass locally and fail in CI. The
# trailing `|| false` makes the failure count under every bash version, which
# is the form the bats documentation gives.
#
# This check uses `[ ]`, which bash 3.2 handles correctly, so it fails
# locally too.

load test_helper

@test "constructs: no assertion line is a bare [[ ]] without || false" {
  local offenders
  offenders="$(grep -nE '^[[:space:]]*\[\[ .*\]\][[:space:]]*$' "$PROJECT_ROOT"/bats-tests/*.bats || true)"
  [ -z "$offenders" ] || {
    echo "These lines end in a bare [[ ]], which bash 3.2 does not count as a failure:"
    echo "$offenders"
    echo "Append || false to each one."
    return 1
  }
}
