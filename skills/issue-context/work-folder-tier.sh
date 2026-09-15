#!/usr/bin/env bash
#
# work-folder-tier.sh — Print which tier names this session's work folder.
#
# Usage: work-folder-tier.sh
#
# STDOUT IS EXACTLY ONE LINE, ALWAYS, AND IT IS ONE OF THESE TOKENS:
#
#   session   the session override set by /set-work-folder is in effect
#   worktree  this worktree's CLAUDE_WORK_FOLDER marker is in effect
#   branch    neither, so placement is derived from the branch
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
_issue_context_work_folder folder tier report || true

printf '%s\n' "$tier"
