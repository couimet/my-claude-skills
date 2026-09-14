#!/usr/bin/env bash
#
# get-issue-folder-path.sh — Print the folder that holds a work item's files.
#
# Resolution has two levels, in this order:
#
#   1. The current session's folder override, when one is set and valid. See
#      session-file.sh for where that file lives and what makes it valid.
#   2. <claude-work-root>[/<segment>]/<identifier>, where the root comes from
#      claude-work-root.sh, the segment from the configured settings (an empty
#      segment omits the directory), and the identifier from the current
#      branch.
#
# Usage:
#   get-issue-folder-path.sh                      session override, else branch
#   get-issue-folder-path.sh --id <identifier>    use the given identifier
#
# --id never consults the override. Naming a work item is an explicit request,
# and the callers that pass --id are the ones that delete a directory or read a
# pointer out of it; an ambient session setting must not retarget those. When
# an override exists and --id bypassed it, that is reported.
#
# STDOUT IS EXACTLY ONE LINE, ALWAYS, AND IT IS A PATH. Callers capture it with
# command substitution and then create the directory it names. A status message
# on stdout would be captured as part of the path and turned into a directory
# named after the message. Every report goes to stderr for that reason.
#
# The chosen folder is reported on stderr on every run, along with any override
# that was found and not used. Without that line, an override silently ignored
# (because its folder is gone, or it belongs to another repository) looks
# exactly like never having set one.
#
# On a branch matching no pattern, with no override, the bare root is printed
# (flat placement, matching the original behavior). The folder is NOT created —
# callers handle that. Invalid input or a wrong argument count prints an error
# to stderr and exits 1.
#
# Settings come from issue-settings.sh (see MY_CLAUDE_SKILLS_CONFIG).

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/session-file.sh"

_root() {
  "$_self_dir/claude-work-root.sh" || {
    echo "get-issue-folder-path: error: could not resolve .claude-work root" >&2
    return 1
  }
}

# _report <message> — say what happened, on stderr, never on stdout.
_report() {
  echo "get-issue-folder-path: $1" >&2
}

# _containment_root — print the physical path of the repository an override
# must live inside, or return 1 outside a repository.
#
# This is the current worktree's toplevel, not the parent of what
# claude-work-root.sh returns. The two differ in a linked worktree, where
# claude-work-root.sh deliberately points at the main checkout so worktrees
# share one .claude-work/. Containment is about the repository the user is
# working in, so a path in a sibling checkout is refused here the same way a
# path in an unrelated repository is.
_containment_root() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$top" ] || return 1
  (cd "$top" && pwd -P) 2>/dev/null
}

# _override_folder <out-var> — resolve this session's override into <out-var>.
#
# Returns 0 only for an override that is absolute, is an existing directory,
# and whose physical path is the containment root or lies under it. Every other
# outcome returns 1, having reported anything the user needs to know. Falling
# back is always safe: refusing to resolve a path because a session file went
# stale would block an unrelated call for an unrelated reason.
_override_folder() {
  local _gifp_out_var="$1" _gifp_folder="" _gifp_reason="" _gifp_phys _gifp_root

  if ! _issue_context_session_file_read _gifp_folder _gifp_reason; then
    case "$_gifp_reason" in
      none) ;; # No override set. Nothing to say.
      duplicate)
        _report "override ignored: more than one session file matches this session id" ;;
      nojq)
        _report "override ignored: jq not found, cannot read the session file" ;;
      version)
        _report "override ignored: session file has an unrecognised version" ;;
      *)
        _report "override ignored: session file is unreadable or malformed" ;;
    esac
    return 1
  fi

  case "$_gifp_folder" in
    /*) ;;
    *)
      _report "override ignored: '$_gifp_folder' is not an absolute path"
      return 1
      ;;
  esac

  if [ ! -d "$_gifp_folder" ]; then
    _report "override ignored: '$_gifp_folder' is not an existing directory"
    return 1
  fi

  # Canonicalise before comparing. A prefix test on the literal string would
  # pass for a path that leaves the repository through .. or through a symlink
  # component and comes back looking contained.
  _gifp_phys="$(cd "$_gifp_folder" && pwd -P 2>/dev/null)" || {
    _report "override ignored: '$_gifp_folder' could not be resolved"
    return 1
  }

  if ! _gifp_root="$(_containment_root)"; then
    _report "override ignored: not inside a git repository, so '$_gifp_folder' cannot be checked"
    return 1
  fi

  if [ "$_gifp_phys" != "$_gifp_root" ] \
      && [ "${_gifp_phys#"$_gifp_root"/}" = "$_gifp_phys" ]; then
    _report "override ignored: '$_gifp_folder' is outside this repository ($_gifp_root)"
    return 1
  fi

  eval "$_gifp_out_var=\"\$_gifp_phys\""
  return 0
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

# _emit <folder> — report the choice on stderr, then print the one stdout line.
# Every successful path ends here, so there is exactly one place that writes
# stdout and exactly one place that says which folder won.
_emit() {
  _report "using $1"
  printf '%s\n' "$1"
}

_main() {
  local identifier folder override=""
  if [ "$#" -eq 2 ] && [ "$1" = "--id" ]; then
    identifier="$("$_self_dir/resolve-issue-id.sh" "$2")" || return 1
    folder="$(_print_folder_for_id "$identifier")" || return 1
    # Naming a work item bypasses the override. Say so when there is one, or
    # the same session resolving two different folders looks like a bug.
    if _override_folder override; then
      _report "override '$override' bypassed: --id names a work item explicitly"
    fi
    _emit "$folder"
    return 0
  fi
  if [ "$#" -eq 0 ]; then
    if _override_folder override; then
      _emit "$override"
      return 0
    fi
    if identifier="$("$_self_dir/branch-issue-id.sh")"; then
      folder="$(_print_folder_for_id "$identifier")" || return 1
      _emit "$folder"
      return 0
    fi
    # Not a work branch and no override: flat placement at the root.
    folder="$(_root)" || return 1
    _emit "$folder"
    return 0
  fi
  echo "usage: get-issue-folder-path.sh [--id <identifier>]" >&2
  return 1
}

_main "$@"
