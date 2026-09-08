#!/usr/bin/env bash
#
# get-issue-folder-path.sh — Print the .claude-work/ folder that holds a work
# item's files. The folder is <claude-work-root>[/<segment>]/<identifier>,
# where the root comes from claude-work-root.sh and the segment from the
# configured settings (an empty segment omits the directory). The identifier
# is resolved from the current branch or supplied with --id.
#
# Usage:
#   get-issue-folder-path.sh                      infer from current branch
#   get-issue-folder-path.sh --id <identifier>    use the given identifier
#
# On a branch matching branchPatterns, or with --id, the folder is printed on
# stdout. On a branch matching no pattern the bare root is printed (flat
# placement, matching today's behavior). The folder is NOT created — callers
# handle that. Invalid input or a wrong argument count prints an error to
# stderr and exits 1.
#
# Settings come from issue-settings.sh (see MY_CLAUDE_SKILLS_CONFIG).

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh"

_root() {
  "$_self_dir/claude-work-root.sh" || {
    echo "get-issue-folder-path: error: could not resolve .claude-work root" >&2
    return 1
  }
}

_print_folder_for_id() {
  local identifier="$1"
  local folder
  # Belt-and-suspenders: callers already validate identifiers and the settings
  # loader validates the segment, but refuse to build an escaping folder path
  # even if a future call path skips one of those checks.
  if ! _issue_settings_is_safe_component "$identifier"; then
    echo "get-issue-folder-path: error: '$identifier' is not usable as a work-item identifier" >&2
    return 1
  fi
  folder="$(_root)" || return 1
  if [ -n "$SETTINGS_SEGMENT" ]; then
    if ! _issue_settings_is_safe_component "$SETTINGS_SEGMENT"; then
      echo "get-issue-folder-path: error: settings segment '$SETTINGS_SEGMENT' is not usable as a path component" >&2
      return 1
    fi
    folder="$folder/$SETTINGS_SEGMENT"
  fi
  printf '%s\n' "$folder/$identifier"
}

_main() {
  local identifier
  if [ "$#" -eq 2 ] && [ "$1" = "--id" ]; then
    identifier="$("$_self_dir/resolve-issue-id.sh" "$2")" || return 1
    _print_folder_for_id "$identifier"
    return $?
  fi
  if [ "$#" -eq 0 ]; then
    if identifier="$("$_self_dir/branch-issue-id.sh")"; then
      _print_folder_for_id "$identifier"
      return $?
    fi
    # Not a work branch: flat placement at the root.
    _root
    return 0
  fi
  echo "usage: get-issue-folder-path.sh [--id <identifier>]" >&2
  return 1
}

_main "$@"
