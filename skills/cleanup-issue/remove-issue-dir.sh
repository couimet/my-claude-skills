#!/usr/bin/env bash
#
# remove-issue-dir.sh — Safely remove a work item's working directory.
#
# This is the ONLY code path that performs rm -rf in the cleanup-issue
# workflow.  ID validation is enforced here, not in prose.
#
# The caller resolves the directory and passes it in. The script does not
# build a path, because the folder a work item lives in depends on which tier
# named it — a session override, this worktree's CLAUDE_WORK_FOLDER marker, or
# the branch — and a script that rebuilt it from a root would remove a
# different directory than the one the user was shown and agreed to.
# get-issue-folder-path.sh --id <id> is what resolves it.
#
# Usage: remove-issue-dir.sh <folder> --id <id>
#
#   <folder>  Absolute path to the work item's directory, as resolved by
#             get-issue-folder-path.sh --id <id>
#   <id>      Work-item ID validated against ^[A-Za-z0-9][A-Za-z0-9._-]*$
#
# What is verified before anything is removed:
#
#   - <folder> is absolute, and its last component is exactly <id>, so the
#     caller cannot hand over a parent directory or a sibling by accident.
#   - <id> passes the regex above, which rejects "." and ".." along with path
#     separators and shell metacharacters.
#   - <id> is not one of the reserved category names (notes, questions,
#     scratchpads, commit-msgs). Under a marker, and under an empty segment,
#     those directories sit at the same level as work-item folders, so the
#     refusal is unconditional rather than tied to a setting.
#   - <folder>'s last component is not a symlink, which is what catches a
#     work-item directory pointed somewhere else entirely. A symlinked parent
#     is fine and stays accepted: only the last component is the one this ID
#     claims.
#
# Output (stdout):
#   The absolute path removed (e.g., /Users/x/project/.claude-work/issues/42).
#
# Exit codes:
#   0  — directory removed (or didn't exist — idempotent). A symlink at the
#        last component is not part of that case: it is refused below rather
#        than read as an absent directory.
#   1  — validation error (see stderr)
#   2  — runtime error (see stderr)

set -euo pipefail

readonly ERR_BAD_ID="R001"
readonly ERR_BAD_FOLDER="R002"
readonly ERR_RM_FAILED="R003"

# --- Validate arguments ---
if [ $# -ne 3 ] || [ "$2" != "--id" ]; then
  echo "remove-issue-dir $ERR_BAD_FOLDER error: usage: remove-issue-dir.sh <folder> --id <id>" >&2
  exit 1
fi

folder="$1"
id="$3"

# Trailing slashes would make the last-component check and rm disagree about
# what they are looking at.
while [ "$folder" != "/" ] && [ "${folder%/}" != "$folder" ]; do
  folder="${folder%/}"
done

# --- Validate folder ---
if [[ "$folder" != /* ]]; then
  echo "remove-issue-dir $ERR_BAD_FOLDER error: folder must be an absolute path, got: $folder" >&2
  exit 1
fi

# --- Validate ID ---
# Must start with alphanumeric (rejects . and ..) and contain only safe chars.
if ! [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "remove-issue-dir $ERR_BAD_ID error: invalid issue ID '$id'. Expected ^[A-Za-z0-9][A-Za-z0-9._-]*\$" >&2
  exit 1
fi

# The category directories are siblings of work-item folders wherever
# placement is flat, and a work item is never legitimately called one of them.
case "$id" in
  notes|questions|scratchpads|commit-msgs)
    echo "remove-issue-dir $ERR_BAD_ID error: '$id' is a reserved directory name, not an issue ID" >&2
    exit 1
    ;;
esac

# --- The folder must be the one this ID names ---
if [ "${folder##*/}" != "$id" ]; then
  echo "remove-issue-dir $ERR_BAD_ID error: folder '$folder' does not end in the issue ID '$id'" >&2
  exit 1
fi

# A symlink at the last component is refused outright, because rm -rf removes
# the link and leaves everything it points at, so the run would report a
# cleanup that did not happen. A symlinked parent is fine and stays accepted:
# only the last component is the one this ID claims. This is checked before
# the directory test below, so a dangling link is refused rather than read as
# an absent directory and reported as an idempotent success.
if [ -L "$folder" ]; then
  echo "remove-issue-dir $ERR_BAD_FOLDER error: folder '$folder' is a symlink; removing it would leave what it points at in place" >&2
  exit 1
fi

# --- Remove ---
if [ -d "$folder" ]; then
  if ! rm -rf "$folder"; then
    echo "remove-issue-dir $ERR_RM_FAILED error: failed to remove $folder" >&2
    exit 2
  fi
fi

printf '%s\n' "$folder"
