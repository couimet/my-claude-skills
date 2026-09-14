#!/usr/bin/env bash
#
# session-file.sh — Owns the per-session folder-override file: where it lives,
# what it is called, what it contains, and how a reader decides to trust it.
# Source this file; do not execute it. It requires issue-settings.sh to have
# been sourced first, for SETTINGS_FILE.
#
# The override exists because placement used to be a function of the branch
# alone, so a repository organised by topic could not say where its files
# belong. A session names a folder once, and every working file that session
# writes goes there.
#
# Why a file and not an environment variable: the process backing a
# conversation is replaced underneath it (a session moved to a background
# spare reports a different CLAUDE_PID and loses the environment it launched
# with), while CLAUDE_CODE_SESSION_ID survives that swap. A variable would
# route one conversation to two places, silently.
#
# Location:
#   <dirname SETTINGS_FILE>/sessions/<session-id>[--<slug>].json
#
# The sessions directory sits beside the settings file so MY_CLAUDE_SKILLS_CONFIG
# relocates both, which is what lets the test suite isolate itself without
# touching a developer's home directory.
#
# Functions defined on source:
#   _issue_context_sessions_dir
#   _issue_context_session_file_read <out-folder-var> <out-reason-var>
#   _issue_context_session_file_matches <out-array-var>
#
# Reading never exits and never prints. Every failure returns non-zero and
# writes a short reason into the caller's variable, so the caller composes its
# own stderr line and decides what to do. A resolver that refused to resolve a
# path because a session file was unreadable would block an unrelated call for
# a reason that has nothing to do with it.

# The document format this reader understands. A file carrying any other
# version is ignored rather than guessed at, so a later format change cannot
# make an old reader do something wrong.
_ISSUE_CONTEXT_SESSION_VERSION=1

# Slug bound for a session filename. The session id already spends 36
# characters; this keeps the readable half from dwarfing it.
_ISSUE_CONTEXT_SESSION_SLUG_MAX=60

# _issue_context_sessions_dir — print the directory holding session files.
# Derived from SETTINGS_FILE so one variable moves the settings and the
# sessions together. Returns 1 when SETTINGS_FILE is unset or empty.
_issue_context_sessions_dir() {
  [ -n "${SETTINGS_FILE:-}" ] || return 1
  # Parameter expansion rather than dirname: this runs on every path
  # resolution, and it must still work when PATH holds nothing, which is how
  # the jq-absent branch below is exercised.
  case "$SETTINGS_FILE" in
    */*) printf '%s/sessions\n' "${SETTINGS_FILE%/*}" ;;
    *) printf './sessions\n' ;;
  esac
}

# _issue_context_session_file_matches <out-array-var> — collect every session
# file belonging to the current session into the named array variable.
#
# Session ids are unique, so at most one session owns a file and the glob
# cannot reach another session's. Both spellings match: <id>.json when the
# writer had no name to work from, and <id>--<slug>.json when it did. Nothing
# ever looks a file up by its slug, so a filename whose slug went stale stays
# cosmetic.
#
# Returns 1 when there is no session id or no sessions directory. An empty
# array with a 0 return means the directory exists and holds nothing for this
# session, which is the ordinary no-override case.
_issue_context_session_file_matches() {
  local _isf_out_var="$1" _isf_dir _isf_candidate
  local -a _isf_found=()

  [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || return 1
  _isf_dir="$(_issue_context_sessions_dir)" || return 1
  [ -d "$_isf_dir" ] || return 1

  for _isf_candidate in "$_isf_dir/${CLAUDE_CODE_SESSION_ID}"*.json; do
    [ -f "$_isf_candidate" ] || continue
    _isf_found+=("$_isf_candidate")
  done

  # eval is how a bash 3.2 function assigns to a caller-named array; macOS
  # ships 3.2, so namerefs (declare -n) are not available. Every local here
  # carries the _isf_ prefix so a caller passing an out-variable named `dir`
  # or `found` assigns to its own variable rather than to this function's.
  eval "$_isf_out_var=()"
  if [ "${#_isf_found[@]}" -gt 0 ]; then
    eval "$_isf_out_var=(\"\${_isf_found[@]}\")"
  fi
  return 0
}

# _issue_context_session_file_read <out-folder-var> <out-reason-var> — read the
# current session's override folder into <out-folder-var>.
#
# Returns 0 when a single well-formed file of a known version yielded a
# non-empty folder. Otherwise returns 1 and writes one of these reasons:
#
#   none        no session id, no sessions directory, or no file for this
#               session. The ordinary case, and the caller reports nothing.
#   duplicate   more than one file matched. Two files cannot both describe one
#               session, so neither is trusted.
#   nojq        jq is absent, so the document cannot be parsed.
#   malformed   unreadable file, invalid JSON, or no usable folder field.
#   version     a version this reader does not understand.
_issue_context_session_file_read() {
  # Every local carries the _isf_ prefix on purpose. A caller naturally names
  # its out-variables `folder` and `reason`, and a local of the same name would
  # shadow them: the eval below would assign to this function's copy and the
  # caller would read back an empty string from a call that returned 0.
  local _isf_out_folder_var="$1" _isf_out_reason_var="$2"
  local -a _isf_matches=()
  local _isf_file _isf_version _isf_folder

  eval "$_isf_out_folder_var=''"
  eval "$_isf_out_reason_var='none'"

  _issue_context_session_file_matches _isf_matches || return 1
  [ "${#_isf_matches[@]}" -ne 0 ] || return 1

  # One writer rule: a session that already has a file gets it replaced in
  # place, never joined by a second under a different slug. Two matches mean
  # that rule was broken by hand or by an older writer, and picking one would
  # be a coin toss the user cannot see.
  if [ "${#_isf_matches[@]}" -gt 1 ]; then
    eval "$_isf_out_reason_var='duplicate'"
    return 1
  fi

  _isf_file="${_isf_matches[0]}"
  [ -r "$_isf_file" ] || { eval "$_isf_out_reason_var='malformed'"; return 1; }

  if ! command -v jq >/dev/null 2>&1; then
    eval "$_isf_out_reason_var='nojq'"
    return 1
  fi

  if ! _isf_version="$(jq -r 'if type == "object" and (.version | type == "number")
                              then .version else empty end' "$_isf_file" 2>/dev/null)" \
      || [ -z "$_isf_version" ]; then
    eval "$_isf_out_reason_var='malformed'"
    return 1
  fi

  if [ "$_isf_version" != "$_ISSUE_CONTEXT_SESSION_VERSION" ]; then
    eval "$_isf_out_reason_var='version'"
    return 1
  fi

  # A reader ignores fields it does not recognise, so a later version can add
  # fields without breaking this one. Only folder is read.
  if ! _isf_folder="$(jq -r 'if (.folder | type == "string") and (.folder | length > 0)
                             then .folder else empty end' "$_isf_file" 2>/dev/null)" \
      || [ -z "$_isf_folder" ]; then
    eval "$_isf_out_reason_var='malformed'"
    return 1
  fi

  # Assign through a quoted expansion of the local so a folder holding spaces
  # or shell metacharacters survives the eval intact.
  eval "$_isf_out_folder_var=\"\$_isf_folder\""
  eval "$_isf_out_reason_var=''"
  return 0
}
