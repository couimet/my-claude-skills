#!/usr/bin/env bash
#
# branch-issue-id.sh — The single owner of branch-to-identifier matching.
#
# Reads the current branch via `git branch --show-current` and matches it
# against the configured branchPatterns in order. The first pattern that
# matches supplies the identifier as its first capture group, which is printed
# on stdout. A branch matching no pattern — or no branch at all (detached
# HEAD, non-repository) — exits 1 and prints nothing: callers branch on the
# exit status and own their own user-facing messaging, and path-resolving
# callers rely on the silence to keep flat placement clean.
#
# Settings come from issue-settings.sh (see MY_CLAUDE_SKILLS_CONFIG).

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh"

branch="$(git branch --show-current 2>/dev/null)" || branch=""
if [ -n "$branch" ]; then
  for pattern in "${SETTINGS_BRANCH_PATTERNS[@]}"; do
    if [[ "$branch" =~ $pattern ]]; then
      if [ -n "${BASH_REMATCH[1]:-}" ]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        exit 0
      fi
      # Matched but captured nothing usable; keep trying later patterns.
    fi
  done
fi
exit 1
