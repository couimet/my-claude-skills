#!/usr/bin/env bash
#
# work-folder.sh — Owns the tier order: which source names this session's work
# folder, and what to say about the ones that lost. Source this file; do not
# execute it. It requires session-file.sh and marker-file.sh to have been
# sourced first, the same way session-file.sh requires issue-settings.sh.
#
# Three tiers, in order:
#
#   session   the session override (session-file.sh), which dies with the
#             session that set it
#   worktree  the CLAUDE_WORK_FOLDER marker (marker-file.sh), which lives at
#             the worktree root until someone deletes it
#   branch    the placement that predates both: <claude-work-root>[/<segment>]
#             /<identifier-from-the-branch>
#
# Session before worktree because the explicit, deliberate, just-typed setting
# should beat the standing one. Both before branch because naming a folder is
# a statement and inferring one from a branch is a default.
#
# This file holds the order exactly once. get-issue-folder-path.sh resolves
# paths with it and work-folder-tier.sh answers which tier won with it, so the
# two can never disagree about precedence.
#
# Functions defined on source:
#   _issue_context_marker_folder <out-folder-var> <out-report-var>
#   _issue_context_work_folder <out-folder-var> <out-tier-var> <out-report-var>
#
# Neither prints. Both collect what a caller should say into <out-report-var>
# as zero or more newline-separated lines, and the caller decides where those
# go. A resolver that printed from here would put a message on stdout one day,
# and stdout is a path.

# _iwfu_usable <path> <out-var> — canonicalise <path> into <out-var>.
#
# Returns 0 on success, or a code naming what was wrong: 2 not absolute, 3 not
# an existing directory, 4 could not be resolved. Both tiers are checked this
# way, so a folder that has been deleted reads the same whichever named it.
#
# Every function in this file carries its own local prefix. A caller names an
# out-variable, and two functions sharing a local name means the callee
# assigns to its own copy while the caller reads back an empty string from a
# call that returned success.
_iwfu_usable() {
  local _iwfu_path="$1" _iwfu_out="$2" _iwfu_phys
  case "$_iwfu_path" in
    /*) ;;
    *) return 2 ;;
  esac
  [ -d "$_iwfu_path" ] || return 3
  # Canonicalise: a path that leaves and re-enters through .. or a symlink
  # should be stored as where it actually is.
  _iwfu_phys="$({ cd "$_iwfu_path" && pwd -P; } 2>/dev/null)" || return 4
  eval "$_iwfu_out=\"\$_iwfu_phys\""
  return 0
}

# _iwfa_append <out-report-var> <line> — add one line to a report.
_iwfa_append() {
  local _iwfa_var="$1" _iwfa_line="$2" _iwfa_cur
  eval "_iwfa_cur=\"\$$_iwfa_var\""
  if [ -n "$_iwfa_cur" ]; then
    eval "$_iwfa_var=\"\$_iwfa_cur
\$_iwfa_line\""
  else
    eval "$_iwfa_var=\"\$_iwfa_line\""
  fi
}

# _issue_context_marker_folder <out-folder-var> <out-report-var> — resolve the
# worktree marker alone, ignoring the session tier.
#
# Returns 0 with a canonical folder, or 1 having recorded why the marker was
# passed over. A --id call uses this: it bypasses the session tier on purpose
# and still honours the marker, because what it guards against is an ephemeral
# setting and the marker is the opposite of ephemeral.
_issue_context_marker_folder() {
  local _iwfm_out_var="$1" _iwfm_report_var="$2"
  local _iwfm_raw="" _iwfm_reason="" _iwfm_phys="" _iwfm_rc=0

  eval "$_iwfm_out_var=''"

  if ! _issue_context_marker_read _iwfm_raw _iwfm_reason; then
    case "$_iwfm_reason" in
      none) ;; # No marker. Nothing to say.
      unreadable)
        _iwfa_append "$_iwfm_report_var" "worktree marker ignored: $_ISSUE_CONTEXT_MARKER_NAME could not be read" ;;
      empty)
        _iwfa_append "$_iwfm_report_var" "worktree marker ignored: $_ISSUE_CONTEXT_MARKER_NAME is empty" ;;
      relative)
        _iwfa_append "$_iwfm_report_var" "worktree marker ignored: $_ISSUE_CONTEXT_MARKER_NAME must hold an absolute path or one starting with ~/" ;;
      *)
        _iwfa_append "$_iwfm_report_var" "worktree marker ignored: $_ISSUE_CONTEXT_MARKER_NAME could not be read" ;;
    esac
    return 1
  fi

  _iwfu_usable "$_iwfm_raw" _iwfm_phys || _iwfm_rc=$?
  case "$_iwfm_rc" in
    0)
      eval "$_iwfm_out_var=\"\$_iwfm_phys\""
      return 0
      ;;
    3)
      _iwfa_append "$_iwfm_report_var" "worktree marker ignored: '$_iwfm_raw' is not an existing directory" ;;
    *)
      _iwfa_append "$_iwfm_report_var" "worktree marker ignored: '$_iwfm_raw' could not be resolved" ;;
  esac
  return 1
}

# _issue_context_work_folder <out-folder-var> <out-tier-var> <out-report-var> —
# resolve the folder for the current session through the tier order.
#
# Returns 0 with the tier set to "session" or "worktree" and the folder
# canonicalised. Returns 1 with the tier set to "branch", meaning the caller
# should fall back to branch-derived placement, having recorded anything the
# user needs to know about a tier that was found and not used. Falling back is
# always safe: refusing to resolve a path because a marker went stale would
# block an unrelated call for an unrelated reason.
_issue_context_work_folder() {
  local _iwfw_out_var="$1" _iwfw_tier_var="$2" _iwfw_report_var="$3"
  local _iwfw_raw="" _iwfw_reason="" _iwfw_phys="" _iwfw_rc=0

  eval "$_iwfw_out_var=''"
  eval "$_iwfw_tier_var='branch'"

  if _issue_context_session_file_read _iwfw_raw _iwfw_reason; then
    _iwfu_usable "$_iwfw_raw" _iwfw_phys || _iwfw_rc=$?
    case "$_iwfw_rc" in
      0)
        eval "$_iwfw_out_var=\"\$_iwfw_phys\""
        eval "$_iwfw_tier_var='session'"
        return 0
        ;;
      2)
        _iwfa_append "$_iwfw_report_var" "override ignored: '$_iwfw_raw' is not an absolute path" ;;
      3)
        _iwfa_append "$_iwfw_report_var" "override ignored: '$_iwfw_raw' is not an existing directory" ;;
      *)
        _iwfa_append "$_iwfw_report_var" "override ignored: '$_iwfw_raw' could not be resolved" ;;
    esac
  else
    case "$_iwfw_reason" in
      none) ;; # No override set. Nothing to say.
      duplicate)
        _iwfa_append "$_iwfw_report_var" "override ignored: more than one session file matches this session id" ;;
      nojq)
        _iwfa_append "$_iwfw_report_var" "override ignored: jq not found, cannot read the session file" ;;
      version)
        _iwfa_append "$_iwfw_report_var" "override ignored: session file has an unrecognised version" ;;
      *)
        _iwfa_append "$_iwfw_report_var" "override ignored: session file is unreadable or malformed" ;;
    esac
  fi

  if _issue_context_marker_folder _iwfw_phys "$_iwfw_report_var"; then
    eval "$_iwfw_out_var=\"\$_iwfw_phys\""
    eval "$_iwfw_tier_var='worktree'"
    return 0
  fi

  return 1
}
