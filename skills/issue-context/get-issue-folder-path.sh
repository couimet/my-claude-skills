#!/usr/bin/env bash
#
# get-issue-folder-path.sh — Print the folder that holds a work item's files.
#
# Resolution has three levels, in this order. The order itself lives in
# work-folder.sh, which work-folder-tier.sh also sources, so which tier wins
# is defined exactly once.
#
#   1. The current session's folder override, when one is set and valid. See
#      session-file.sh for where that file lives and what makes it valid.
#   2. This worktree's CLAUDE_WORK_FOLDER marker. See marker-file.sh.
#   3. <claude-work-root>[/<segment>]/<identifier>, where the root comes from
#      claude-work-root.sh, the segment from the configured settings (an empty
#      segment omits the directory), and the identifier from the current
#      branch.
#
# Both override tiers name a final work folder, so <folder>/notes/ and its
# siblings fall out of target-path.sh with no identifier directory between.
#
# Usage:
#   get-issue-folder-path.sh                      session, else marker, else branch
#   get-issue-folder-path.sh --id <identifier>    use the given identifier
#
# --id never consults the session override. Naming a work item is an explicit
# request, and the callers that pass --id are the ones that delete a directory
# or read a pointer out of it; an ambient session setting must not retarget
# those. It does honour the worktree marker, as <marker>/<identifier> with no
# segment between, because what the bypass guards against is a setting made in
# passing and the marker is the opposite of that: a file at the worktree root
# that git status names every day. When a session override existed and --id
# bypassed it, that is reported.
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
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/marker-file.sh"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/work-folder.sh"

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

# _report_lines <report> — print each line of a work-folder.sh report.
# work-folder.sh never prints; it hands back what a caller should say, and this
# is the one place that says it.
_report_lines() {
  local _gifp_line
  [ -n "$1" ] || return 0
  while IFS= read -r _gifp_line; do
    [ -n "$_gifp_line" ] || continue
    _report "$_gifp_line"
  done <<EOF
$1
EOF
}

_print_folder_for_id() {
  local identifier="$1" folder="" reason=""
  if _issue_context_branch_folder "$identifier" folder reason; then
    printf '%s\n' "$folder"
    return 0
  fi
  case "$reason" in
    identifier)
      echo "get-issue-folder-path: error: '$identifier' is not usable as a work-item identifier" >&2 ;;
    segment)
      echo "get-issue-folder-path: error: settings segment '$SETTINGS_SEGMENT' is not usable as a path component" >&2 ;;
    *)
      echo "get-issue-folder-path: error: could not resolve .claude-work root" >&2 ;;
  esac
  return 1
}

# _emit <folder> — report the choice on stderr, then print the one stdout line.
# Every successful path ends here, so there is exactly one place that writes
# stdout and exactly one place that says which folder won.
_emit() {
  _report "using $1"
  printf '%s\n' "$1"
}

_main() {
  # shellcheck disable=SC2034 # tier is an out-variable filled by work-folder.sh
  local identifier folder marker="" tier="" report="" bypassed=""
  if [ "$#" -eq 2 ] && [ "$1" = "--id" ]; then
    identifier="$("$_self_dir/resolve-issue-id.sh" "$2")" || return 1
    # The marker is honoured and the session override is not. <marker>/<id>
    # carries no segment: under a marker the ambient files are flat, so a
    # segment directory would name a level nothing else uses.
    if _issue_context_marker_folder marker report; then
      folder="$marker/$identifier"
    else
      folder="$(_print_folder_for_id "$identifier")" || return 1
    fi
    _report_lines "$report"
    # Naming a work item bypasses the session override. Say so when there is
    # one, or the same session resolving two different folders looks like a bug.
    report=""
    if _issue_context_session_file_read bypassed report; then
      _report "override '$bypassed' bypassed: --id names a work item explicitly"
    fi
    _emit "$folder"
    return 0
  fi
  if [ "$#" -eq 0 ]; then
    if _issue_context_work_folder folder tier report; then
      _report_lines "$report"
      _emit "$folder"
      return 0
    fi
    _report_lines "$report"
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
