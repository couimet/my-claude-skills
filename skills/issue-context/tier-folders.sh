#!/usr/bin/env bash
#
# tier-folders.sh — Print the folder every work-folder tier names right now,
# in tier order, so a caller can see the folders that lost as well as the one
# that won.
#
# Usage:
#   tier-folders.sh                 every tier that resolves
#   tier-folders.sh --no-session    the same, with the session tier left out
#
# Output (stdout), one line per tier that resolves, in tier order:
#   <tier><TAB><folder>
#
#   session   the session override set by /set-work-folder
#   worktree  this worktree's CLAUDE_WORK_FOLDER marker
#   branch    <claude-work-root>[/<segment>]/<identifier-from-the-branch>, or
#             the bare root when the branch matches no pattern
#
# THE FIRST LINE IS THE WINNER. Without --no-session it is always the folder
# get-issue-folder-path.sh prints with no argument, because both read the same
# checks in work-folder.sh. A tier that is not set, or that is set and refused
# (a folder that is gone, a malformed file), prints no line. The branch line is
# always present on success.
#
# --no-session answers for the tiers a worktree marker competes with. A marker
# never outranks a session override, so what a marker change hides is measured
# against the worktree and branch tiers alone.
#
# Why it exists: the resolver prints one folder, which is right for a caller
# that writes a file and wrong for a caller that asks what a tier change left
# behind. set-work-folder.sh compares the winner before and after it writes,
# and find-waves.sh looks in the folders that lost when the winner has no
# questions directory.
#
# Nothing is printed on stderr: the resolver already says which folder it chose
# and why, and a second voice saying it again would double every line.
#
# Exit codes:
#   0  — success (at least the branch line was printed)
#   1  — wrong argument form, or the .claude-work root could not be resolved

set -euo pipefail

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh" 2>/dev/null
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/session-file.sh"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/marker-file.sh"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/work-folder.sh"

with_session=1
if [ "$#" -eq 1 ] && [ "$1" = "--no-session" ]; then
  with_session=0
elif [ "$#" -ne 0 ]; then
  echo "usage: tier-folders.sh [--no-session]" >&2
  exit 1
fi

# reason and report are out-variables the helpers fill and this script does
# not read: a refused tier simply prints no line, and saying why belongs to
# get-issue-folder-path.sh.
raw=""
# shellcheck disable=SC2034
reason=""
folder=""
# shellcheck disable=SC2034
report=""

# The session tier, checked the way _issue_context_work_folder checks it: a
# file that reads, then a folder that is usable.
if [ "$with_session" -eq 1 ] && _issue_context_session_file_read raw reason; then
  if _iwfu_usable "$raw" folder; then
    printf 'session\t%s\n' "$folder"
  fi
fi

if _issue_context_marker_folder folder report; then
  printf 'worktree\t%s\n' "$folder"
fi

if identifier="$("$_self_dir/branch-issue-id.sh" 2>/dev/null)"; then
  _issue_context_branch_folder "$identifier" folder reason || exit 1
else
  folder="$("$_self_dir/claude-work-root.sh" 2>/dev/null)" || exit 1
fi
printf 'branch\t%s\n' "$folder"
