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

# _require_enforced_permission_bits — skip the calling test when this process
# can walk through mode bits.
#
# A process holding CAP_DAC_OVERRIDE, root in a container being the usual case,
# enters a mode 000 directory and writes to an unwritable one, so a chmod-based
# denial denies nothing and every assertion resting on it fails. Probing rather
# than reading `id -u`: the uid misses a non-root process carrying the
# capability, and misfires on a filesystem that ignores mode bits altogether.
# The probe asks the filesystem the same question the test does.
_require_enforced_permission_bits() {
  local probe="$TEST_TEMP_DIR/.perm-probe" bypassed=0
  mkdir -p "$probe"
  chmod 000 "$probe"
  if (cd "$probe" && : > probe-file) 2>/dev/null; then
    bypassed=1
  fi
  chmod 755 "$probe"
  rm -rf "$probe"
  if [ "$bypassed" -eq 1 ]; then
    skip "permission bits are not enforced for this process"
  fi
}
