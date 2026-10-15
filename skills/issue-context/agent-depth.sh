#!/usr/bin/env bash
#
# agent-depth.sh — Owns the agent depth record: how deep in a chain of agents
# that start agents a session sits. Source this file; do not execute it. It
# requires issue-settings.sh to have been sourced first, for SETTINGS_FILE.
#
# A session the user started is depth 0. A background agent that a depth-0
# session started with launch-agent.sh --bg is depth 1, and so on.
# launch-agent.sh refuses a launch that would go past launchAgentMaxDepth,
# because nothing else stops a chain of agents that start agents, and each
# one costs tokens.
#
# Why a record and not something the child can see for itself: Claude Code
# 2.1.296 gives a background session no sign of its depth.
# CLAUDE_CODE_CHILD_SESSION reads 1 in a session the user started too,
# `claude --bg` does not pass the caller's environment to the child, and it
# ignores --session-id, so the parent cannot choose the child's id before the
# launch. What the parent does learn is the job id that `claude --bg` prints,
# and that id is the first 8 characters of the child's session id. A
# `claude --bg --resume` restart keeps the session id, so the record survives
# /resume-agent.
#
# The record is written right after the dispatch, so a child that starts a
# launch in its first second could read no record. A child spends that second
# loading its context, and no model turn is that fast, so the window is
# accepted rather than closed.
#
# Location:
#   <dirname SETTINGS_FILE>/agent-depth/<job id>
#
# Beside the sessions directory, so MY_CLAUDE_SKILLS_CONFIG moves both and the
# test suite never touches a developer's home. Contents: one line, the depth
# as a non-negative integer. Nothing prunes the records: each is a few bytes,
# and a record removed too early would reset a live chain to depth 0.
#
# Functions defined on source:
#   _issue_context_agent_depth_dir
#   _issue_context_agent_depth_read <out-depth-var>
#   _issue_context_agent_depth_write <job-id> <depth>
#
# None prints. Each failure returns non-zero, and the caller says why.

# _issue_context_agent_depth_dir — print the directory that holds the depth
# records. Returns 1 when SETTINGS_FILE is unset or empty.
_issue_context_agent_depth_dir() {
  [ -n "${SETTINGS_FILE:-}" ] || return 1
  case "$SETTINGS_FILE" in
    */*) printf '%s/agent-depth\n' "${SETTINGS_FILE%/*}" ;;
    *) printf './agent-depth\n' ;;
  esac
}

# _issue_context_agent_depth_key_ok <key> — return 0 when <key> can name a
# record file: letters, digits, "_" and "-" only, so no key reaches outside
# the directory.
_issue_context_agent_depth_key_ok() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}

# _issue_context_agent_depth_read <out-depth-var> — read the depth of the
# current session into <out-depth-var>.
#
# Returns 0 with depth 0 when CLAUDE_CODE_SESSION_ID is unset (a plain shell)
# or when the session has no record (a session the user started). Returns 0
# with the recorded depth otherwise. Returns 1 when a record exists and holds
# no non-negative integer, or cannot be read: the limit is the hard
# safeguard, so a damaged record refuses rather than reads as 0.
_issue_context_agent_depth_read() {
  local _iad_out_var="$1" _iad_key _iad_dir _iad_file _iad_line=""

  eval "$_iad_out_var=0"

  [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || return 0
  _iad_key="${CLAUDE_CODE_SESSION_ID:0:8}"
  _issue_context_agent_depth_key_ok "$_iad_key" || return 1
  _iad_dir="$(_issue_context_agent_depth_dir)" || return 1
  _iad_file="$_iad_dir/$_iad_key"
  [ -e "$_iad_file" ] || return 0
  [ -f "$_iad_file" ] && [ -r "$_iad_file" ] || return 1
  IFS= read -r _iad_line < "$_iad_file" || _iad_line="${_iad_line:-}"
  # Nine digits at most, so the arithmetic below cannot overflow into a
  # small depth.
  [[ "$_iad_line" =~ ^[0-9]{1,9}$ ]] || return 1
  # 10# keeps a leading zero from reading as octal.
  eval "$_iad_out_var=\$((10#\$_iad_line))"
  return 0
}

# _issue_context_agent_depth_write <job-id> <depth> — record <depth> for the
# session whose job id is <job-id>. Written to a temporary file and renamed, so
# a reader sees the old record or the new one, never half of one.
_issue_context_agent_depth_write() {
  local _iaw_key="$1" _iaw_depth="$2" _iaw_dir _iaw_tmp
  _issue_context_agent_depth_key_ok "$_iaw_key" || return 1
  [[ "$_iaw_depth" =~ ^[0-9]{1,9}$ ]] || return 1
  _iaw_dir="$(_issue_context_agent_depth_dir)" || return 1
  mkdir -p "$_iaw_dir" 2>/dev/null || return 1
  _iaw_tmp="$(mktemp "$_iaw_dir/.tmp-XXXXXX" 2>/dev/null)" || return 1
  if ! printf '%s\n' "$_iaw_depth" > "$_iaw_tmp" \
    || ! mv -f "$_iaw_tmp" "$_iaw_dir/$_iaw_key"; then
    rm -f "$_iaw_tmp"
    return 1
  fi
  return 0
}
