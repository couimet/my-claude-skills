#!/usr/bin/env bash
#
# work-folder-tier.sh — Print which tier names this session's work folder.
#
# Usage:
#   work-folder-tier.sh              the tier a no-argument resolution uses
#   work-folder-tier.sh --id <id>    the tier a --id resolution uses
#
# ON SUCCESS STDOUT IS EXACTLY ONE LINE, AND IT IS ONE OF THESE TOKENS:
#
#   session   the session override set by /set-work-folder is in effect
#   worktree  this worktree's CLAUDE_WORK_FOLDER marker is in effect
#   branch    neither, so placement is derived from the branch
#
# The two forms answer for the two resolutions get-issue-folder-path.sh
# performs, and a caller must ask in the form it resolved in. A --id call
# bypasses the session tier and still honours the marker, so --id here never
# answers "session"; asking the bare form about a path resolved with --id
# reports the tier that lost. The identifier does not change which tier wins.
# It is taken so the call mirrors the resolution it describes and cannot be
# read as the other form.
#
# A skill cannot work this out from the resolved path, because <marker>/42 and
# <root>/issues/42 are both just paths, and it cannot check for the marker file
# either, because the session tier outranks the marker: a marker that exists
# may have lost. /cleanup-issue asks this so its confirmation prompt can say
# what a delete will and will not remove, which is the worst place in the
# system to be wrong.
#
# The tier order itself lives in work-folder.sh, sourced by this script and by
# get-issue-folder-path.sh, so the answer here and the path there cannot
# disagree.
#
# Nothing is printed on stderr: the resolver already says which folder it chose
# and why, and a second voice saying it again would double every line.
#
# Exit codes:
#   0  — success (a token was printed)
#   1  — wrong argument form (usage error on stderr, nothing on stdout)

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

# folder and report are out-variables the helper fills and this script does not
# read: the tier is the whole answer here, and the folder and the reporting
# belong to get-issue-folder-path.sh.
# shellcheck disable=SC2034
folder=""
tier=""
# shellcheck disable=SC2034
report=""

if [ "$#" -eq 2 ] && [ "$1" = "--id" ]; then
  # The same two tiers --id resolves through, in the same order: the marker is
  # honoured and the session override is not.
  if _issue_context_marker_folder folder report; then
    tier="worktree"
  else
    tier="branch"
  fi
elif [ "$#" -eq 0 ]; then
  _issue_context_work_folder folder tier report || true
else
  echo "usage: work-folder-tier.sh [--id <identifier>]" >&2
  exit 1
fi

printf '%s\n' "$tier"
