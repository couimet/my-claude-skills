#!/usr/bin/env bash
#
# check-script-headers.sh — Every script carries a header comment block.
#
# A script's behaviour is documented in its own header, not in the prose of
# the skills that call it. Skill prose costs context on every invocation and
# drifts from the code it describes; a header does neither. This check holds
# that convention.
#
# A header is at least five comment lines in the first fifteen lines of the
# file, after the shebang. Five is enough for a name, a usage line, and what
# the script outputs, and short enough that a genuinely tiny helper is not
# forced to pad.
#
# Every *.sh and *.bash file is checked, which is the set lint-sh covers.
#
# Usage: check-script-headers.sh [<dir> ...]   (default: skills/ and scripts/)
#
# Exit codes:
#   0  — every script has a header
#   1  — one or more do not (listed on stderr)
#   2  — usage error

set -euo pipefail

MIN_HEADER_LINES=5

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '3,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$#" -gt 0 ]; then
  dirs=("$@")
else
  dirs=("$root/skills" "$root/scripts")
fi

for d in "${dirs[@]}"; do
  [ -d "$d" ] || { echo "check-script-headers H002 error: '$d' is not a directory" >&2; exit 2; }
done

missing=0
while IFS= read -r script; do
  count="$(sed -n '2,16p' "$script" | grep -c '^#' || true)"
  if [ "$count" -lt "$MIN_HEADER_LINES" ]; then
    echo "${script#"$root"/}: header is $count comment lines, needs at least $MIN_HEADER_LINES" >&2
    missing=$((missing + 1))
  fi
done < <(find "${dirs[@]}" -type f \( -name '*.sh' -o -name '*.bash' \) | sort)

if [ "$missing" -gt 0 ]; then
  echo "check-script-headers: $missing script(s) without a header block. Say what the script does, what it prints, and how it exits." >&2
  exit 1
fi
