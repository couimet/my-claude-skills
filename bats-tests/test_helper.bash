#!/usr/bin/env bash

# Shared test helper for Bats test suites.
# Sources this file from .bats files via: load test_helper

# Resolve the project root (parent of bats-tests/)
# shellcheck disable=SC2034
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# _stub_path_without <dir> <tool> — build <dir> as a PATH directory holding a
# symlink to every executable on the current PATH except <tool>, and print it.
#
# Hiding one tool cannot be done by trimming PATH. The tool shares a directory
# with the ones the script under test still needs, and emptying PATH breaks the
# script before it starts: the shebang is /usr/bin/env bash, and env looks bash
# up on PATH. One `ln -s` per source directory rather than one per file keeps
# this fast, and a collision failing is what makes the earlier PATH entry win,
# the same precedence a real lookup has.
_stub_path_without() {
  local out="$1" hide="$2" d
  local -a dirs=()
  mkdir -p "$out"
  IFS=: read -ra dirs <<< "$PATH"
  for d in "${dirs[@]}"; do
    if [ -d "$d" ]; then
      ln -s "$d"/* "$out"/ 2>/dev/null || true
    fi
  done
  rm -f "$out/$hide"
  printf '%s' "$out"
}

# _stub_failing <dir> <tool> — put a <tool> that always fails first on a PATH
# built from <dir>, and print that PATH. Used where the failure has to come
# from the tool rather than from the filesystem, which is the only way to reach
# an error branch guarding a command that does not fail on a permission change.
_stub_failing() {
  local dir="$1" tool="$2"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$dir/$tool"
  chmod +x "$dir/$tool"
  printf '%s:%s' "$dir" "$PATH"
}
