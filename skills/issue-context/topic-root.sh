#!/usr/bin/env bash
#
# topic-root.sh — Owns the topic root: the directory under which a topic slug
# resolves. Source this file; do not execute it. It requires issue-settings.sh
# to have been sourced first, for SETTINGS_LAUNCH_AGENT_DEFAULT_FOLDER,
# SETTINGS_LOAD_STATUS, and SETTINGS_FILE.
#
# The topic root is the launchAgentDefaultFolder setting when it is set, and
# the root of the main checkout of the current repository when it is not.
# launch-agent.sh creates a topic folder under it, resume-agent.sh finds one,
# and fork-side-item.sh lists the side folders in it. One definition keeps the
# three from resolving one slug to three places.
#
# Functions defined on source:
#   _issue_context_topic_root <out-root-var> <out-reason-var>
#
# Reading never exits and never prints. Every failure returns non-zero and
# writes a short reason into the caller's variable, so each caller composes its
# own error line, with its own code.

# _issue_context_topic_root <out-root-var> <out-reason-var> — resolve the topic
# root into <out-root-var>, with no trailing slash.
#
# Returns 0 with the root. Otherwise returns 1 and writes one of these reasons:
#
#   settings  a settings file is there and could not be read, so the setting
#             is unknown. A fall-back to the repository root here would put
#             the topic in the code repository the setting exists to avoid.
#   relative  the setting is not an absolute path. It expands nothing, so it
#             is checked exactly as written.
#   missing   the setting names no existing directory.
#   norepo    the setting is empty and the current directory is in no git
#             repository, so there is no root to fall back to.
_issue_context_topic_root() {
  # Every local carries the _itr_ prefix so a caller passing out-variables
  # named `root` or `reason` assigns to its own rather than to these.
  local _itr_out_root_var="$1" _itr_out_reason_var="$2"
  local _itr_root _itr_work_root

  eval "$_itr_out_root_var=''"
  eval "$_itr_out_reason_var=''"

  if [ "$SETTINGS_LOAD_STATUS" = "failed" ]; then
    eval "$_itr_out_reason_var='settings'"
    return 1
  fi

  _itr_root="$SETTINGS_LAUNCH_AGENT_DEFAULT_FOLDER"
  if [ -n "$_itr_root" ]; then
    case "$_itr_root" in
      /*) ;; # kcov-exclude-line
      *)
        eval "$_itr_out_reason_var='relative'"
        return 1
        ;;
    esac
    if [ ! -d "$_itr_root" ]; then
      eval "$_itr_out_reason_var='missing'"
      return 1
    fi
    while [ "$_itr_root" != "/" ] && [ "${_itr_root%/}" != "$_itr_root" ]; do
      _itr_root="${_itr_root%/}"
    done
  else
    # claude-work-root.sh reports <main checkout root>/.claude-work, and it is
    # used here for the half of its job this needs: finding the main checkout
    # through a linked worktree. Topic folders sit at that root.
    # BASH_SOURCE[0] inside a function names the file that defined it, so this
    # finds the sibling script whichever script sourced this file.
    _itr_work_root="$("$(dirname "${BASH_SOURCE[0]}")/claude-work-root.sh" 2>/dev/null)" || {
      eval "$_itr_out_reason_var='norepo'"
      return 1
    }
    _itr_root="$(dirname "$_itr_work_root")"
  fi

  eval "$_itr_out_root_var=\"\$_itr_root\""
  return 0
}
