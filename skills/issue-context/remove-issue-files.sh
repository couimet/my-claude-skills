#!/usr/bin/env bash
#
# remove-issue-files.sh — Delete the issue files that /create-github-issue and
# /create-jira-issue write with /note, after a clean run.
#
# Each file repeats text that the draft and the filed issue already hold. A
# repository that tracks its notes folder would otherwise commit the files
# with the real notes.
#
# The script deletes a path only when the path is a regular file (not a
# symlink) and its name has the /note form of an issue file:
#
#   ^[0-9]{8}-[0-9]{6}(-[0-9]{3})?-issue-(body|title|payload)\.[A-Za-z0-9]+$
#
# The name guard keeps a wrong argument from deleting a real note. For each
# other path, the script deletes nothing, names the path on stderr, and goes
# on to the next path.
#
# Usage: remove-issue-files.sh <path> [<path> ...]
#
# Output:
#   stdout: one "removed <path>" line for each deleted file
#   stderr: one error line for each path that stays
#
# Exit codes:
#   0  — each path was deleted
#   1  — no path given, or at least one path stays (see stderr)

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: remove-issue-files.sh <path> [<path> ...]

Deletes each path that is a regular file with the name of an issue file:
<stamp>-issue-body.<ext>, <stamp>-issue-title.<ext>, or
<stamp>-issue-payload.<ext>. Refuses every other path.

  --help  Show this help message
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

readonly ERR_ARGS="I001"
readonly ERR_REFUSED="I002"
readonly ERR_RM="I003"

if [ "$#" -eq 0 ]; then
  echo "remove-issue-files $ERR_ARGS error: expected at least one path" >&2
  usage >&2
  exit 1
fi

readonly NAME_RE='^[0-9]{8}-[0-9]{6}(-[0-9]{3})?-issue-(body|title|payload)\.[A-Za-z0-9]+$'

status=0
for path in "$@"; do
  name="${path##*/}"
  if [ -L "$path" ] || [ ! -f "$path" ] || ! [[ "$name" =~ $NAME_RE ]]; then
    echo "remove-issue-files $ERR_REFUSED error: not an issue file, kept: $path" >&2
    status=1
    continue
  fi
  if rm -f -- "$path"; then
    echo "removed $path"
  else
    echo "remove-issue-files $ERR_RM error: could not delete: $path" >&2
    status=1
  fi
done

exit "$status"
