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
# safety check: it must be usable as one path segment and one branch segment,
# which rejects empty values, leading/trailing dots or slashes, and any
# whitespace. A URL-shaped value that matches no pattern, an identifier that
# fails the safety check, or the wrong argument count prints an error to
# stderr and exits 1 — refusing is safer than inventing an identifier.
#
# Settings come from issue-settings.sh (see MY_CLAUDE_SKILLS_CONFIG).

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh"

_is_url_shaped() {
  [[ "$1" == *"://"* ]]
}

# An identifier must be usable as a single path segment and a single branch
# segment: non-empty, no leading/trailing dot or slash, no whitespace.
_identifier_is_safe() {
  local id="$1"
  [ -n "$id" ] || return 1
  case "$id" in
    .* | /* | */ | *.) return 1 ;;
  esac
  case "$id" in
    *[[:space:]]*) return 1 ;;
  esac
  return 0
}

_main() {
  local arg="$1"
  local pattern id
  if _is_url_shaped "$arg"; then
    for pattern in "${SETTINGS_URL_PATTERNS[@]}"; do
      if [[ "$arg" =~ $pattern ]]; then
        id="${BASH_REMATCH[1]:-}"
        if [ -n "$id" ]; then
          printf '%s\n' "$id"
          return 0
        fi
        # Matched but captured nothing usable; keep trying later patterns.
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
