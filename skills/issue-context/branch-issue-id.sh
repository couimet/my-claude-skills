#!/usr/bin/env bash
#
# branch-issue-id.sh — Resolve the current branch's work-item identifier.
#
# Reads the current branch via `git branch --show-current` and resolves it
# through the shared matcher in issue-settings.sh, which applies the
# configured branchPatterns in order and prints the first pattern's capture
# group one when it is usable as one path segment. The matcher is shared with
# render-branch-template.sh so a branch /start-issue renders and a branch this
# gate recognizes always parse back to the same identifier. A branch matching
# no pattern — or no branch at all (detached HEAD, non-repository) — exits 1
# and prints nothing: callers branch on the exit status and own their own
# user-facing messaging, and path-resolving callers rely on the silence to
# keep flat placement clean.
#
# Settings come from issue-settings.sh (see MY_CLAUDE_SKILLS_CONFIG).

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh"

branch="$(git branch --show-current 2>/dev/null)" || branch=""
if [ -n "$branch" ] && _issue_settings_branch_identifier "$branch"; then
  exit 0
fi
exit 1
