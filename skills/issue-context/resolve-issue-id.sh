#!/usr/bin/env bash
#
# resolve-issue-id.sh — Resolve one argument, a tracker URL or a bare
# identifier, to a canonical work-item identifier.
#
# Usage: resolve-issue-id.sh <URL-or-identifier>
#
# A value carrying a tracker-URL shape (it contains a scheme, e.g. https://)
# is matched against the configured urlPatterns in order; the first pattern
# that matches supplies the identifier as its first capture group. A value
# without a URL shape is a bare identifier and is printed verbatim after the
# safety check. Every identifier — bare or captured from a URL pattern — must
# be usable as one path segment and one branch segment, which rejects empty
# values, ".", "..", anything containing an internal "/", leading/trailing
# dots or slashes, and any whitespace. A URL-shaped value that matches no
# pattern or whose capture fails the safety check, an identifier that fails
# the safety check, or the wrong argument count prints an error to stderr and
# exits 1 — refusing is safer than inventing an identifier.
#
# Settings come from issue-settings.sh (see MY_CLAUDE_SKILLS_CONFIG).

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh"

_is_url_shaped() {
  [[ "$1" == *"://"* ]]
}

# An identifier must be usable as a single path segment and a single branch
# segment. This is the single-path-component invariant shared by every
# issue-context boundary (see _issue_settings_is_safe_component).
_identifier_is_safe() {
  _issue_settings_is_safe_component "$1"
}

_main() {
  local arg="$1"
  local pattern id
  if _is_url_shaped "$arg"; then
    for pattern in "${SETTINGS_URL_PATTERNS[@]}"; do
      if [[ "$arg" =~ $pattern ]]; then
        id="${BASH_REMATCH[1]:-}"
        if [ -n "$id" ] && _identifier_is_safe "$id"; then
          printf '%s\n' "$id"
          return 0
        fi
        # Matched but captured nothing usable (empty or unsafe); keep trying
        # later patterns.
      fi
    done
    echo "resolve-issue-id: error: no url pattern matched '$arg'" >&2
    return 1
  fi
  if _identifier_is_safe "$arg"; then
    printf '%s\n' "$arg"
    return 0
  fi
  echo "resolve-issue-id: error: '$arg' is not usable as a work-item identifier" >&2
  return 1
}

if [ "$#" -eq 1 ]; then
  _main "$1"
else
  echo "usage: resolve-issue-id.sh <URL-or-identifier>" >&2
  exit 1
fi
