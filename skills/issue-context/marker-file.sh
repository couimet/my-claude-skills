#!/usr/bin/env bash
#
# marker-file.sh — Owns the per-worktree work-folder marker: where it lives,
# what it is called, what it holds, and how a reader decides to trust it.
# Source this file; do not execute it.
#
# The marker exists because the session override (see session-file.sh) dies
# with the session, while grouping one topic's working files is work that
# spans days. A worktree names its work folder once, in a file at its own
# root, and every session opened there writes to that folder.
#
# Why the worktree root and not .claude-work/: claude-work-root.sh resolves
# .claude-work/ to the main checkout so every linked worktree shares one copy,
# which is the opposite of what this needs. Two worktrees of one repository
# must be able to point at different folders, or at none, independently.
#
# Location:
#   <git rev-parse --show-toplevel>/CLAUDE_WORK_FOLDER
#
# Contents: the first line, in one of two forms.
#
#   path  an absolute path, or a path whose leading "~/" expands against
#         $HOME. Every session of the worktree writes to that folder.
#   mode  a line that starts with "{", such as {"mode": "require-override"}.
#         It names no folder. It sets a rule for the sessions of the
#         worktree instead.
#
# The one mode today is require-override: each session must set its own
# session folder before it writes a working file. A repository that keeps its
# working files in topic folders commits such a marker, because one path would
# send every session to one topic. Writers refuse with no session folder;
# readers fall through to the branch tier. See work-folder.sh and
# target-path.sh.
#
# The mode is a value of a set, not an on/off flag, so a later mode extends
# the set and the earlier modes keep their meaning.
#
# Neither form needs jq. The resolver already treats a missing jq as a reason
# to ignore the session override, and a marker that needed jq would let one
# absent tool take out two tiers at once. The mode form is matched against one
# fixed shape, a single "mode" key with a lowercase value, and any other line
# that starts with "{" is a mode this reader cannot parse. A reader that does
# not know a mode must refuse a write rather than ignore the marker, because
# ignoring it is what the mode exists to prevent.
#
# The file is deliberately not gitignored. It sits at the worktree root where
# git status names it every day, which is the point: an override you cannot
# stop seeing is one you cannot forget you set.
#
# Functions defined on source:
#   _issue_context_marker_path
#   _issue_context_marker_read <out-folder-var> <out-reason-var>
#   _issue_context_marker_mode <out-mode-var>
#
# Reading never exits and never prints. Every failure returns non-zero and
# writes a short reason into the caller's variable, so the caller composes its
# own stderr line and decides what to do.

# The marker's filename. Undotted and uppercase so it sorts beside CLAUDE.md
# and README.md and no explorer setting can hide it.
_ISSUE_CONTEXT_MARKER_NAME="CLAUDE_WORK_FOLDER"

# _issue_context_marker_path — print the marker's path for the current
# worktree. Returns 1 outside a git repository, where there is no worktree
# root for the file to sit at.
_issue_context_marker_path() {
  local _imf_top
  _imf_top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$_imf_top" ] || return 1
  printf '%s/%s\n' "$_imf_top" "$_ISSUE_CONTEXT_MARKER_NAME"
}

# _issue_context_marker_read <out-folder-var> <out-reason-var> — read this
# worktree's marker into <out-folder-var>.
#
# Returns 0 when the file held a usable path. Otherwise returns 1 and writes
# one of these reasons:
#
#   none        no worktree, or no marker file. The ordinary case, and the
#               caller reports nothing.
#   unreadable  the file exists and could not be read.
#   empty       the file held nothing but whitespace.
#   mode        the line is the mode form, which names no folder. Ask
#               _issue_context_marker_mode for the mode.
#   relative    the path is neither absolute nor a leading "~/".
#
# The path is returned as read, expanded but not canonicalised and not checked
# against the filesystem, which is what the session reader does too: whether a
# folder exists is the resolver's question, asked the same way for both tiers.
_issue_context_marker_read() {
  # Every local carries the _imf_ prefix so a caller passing out-variables
  # named `folder` or `reason` assigns to its own rather than to these.
  local _imf_out_folder_var="$1" _imf_out_reason_var="$2"
  local _imf_file _imf_line _imf_folder _imf_tilde

  eval "$_imf_out_folder_var=''"
  eval "$_imf_out_reason_var='none'"

  _imf_file="$(_issue_context_marker_path)" || return 1
  [ -f "$_imf_file" ] || return 1
  [ -r "$_imf_file" ] || { eval "$_imf_out_reason_var='unreadable'"; return 1; }

  # First line only. A file with more in it is not an error: the format is one
  # path, and refusing a stray trailing newline or a second line would fail a
  # marker that is doing its job.
  IFS= read -r _imf_line < "$_imf_file" || _imf_line="${_imf_line:-}"

  _imf_line="${_imf_line#"${_imf_line%%[![:space:]]*}"}"
  _imf_line="${_imf_line%"${_imf_line##*[![:space:]]}"}"
  [ -n "$_imf_line" ] || { eval "$_imf_out_reason_var='empty'"; return 1; }

  case "$_imf_line" in
    "{"*) eval "$_imf_out_reason_var='mode'"; return 1 ;;
  esac

  # A leading "~/" and nothing else. Reading a file performs no shell
  # expansion, and this is the one form a person writes by hand in a file they
  # author themselves. "~user" is left alone: it is not what anyone types here,
  # and guessing at another account's home would be worse than refusing.
  # The tilde is built rather than written: spelled literally, in a pattern or
  # in an assignment, it reads to a linter as a path that failed to expand,
  # which is the opposite of what happens here. It is matched, then expanded.
  _imf_tilde="$(printf '\176/')"
  case "$_imf_line" in
    "$_imf_tilde"*) _imf_folder="${HOME:-}/${_imf_line#"$_imf_tilde"}" ;;
    *) _imf_folder="$_imf_line" ;;
  esac

  case "$_imf_folder" in
    /*) ;; # kcov-exclude-line
    *) eval "$_imf_out_reason_var='relative'"; return 1 ;;
  esac

  eval "$_imf_out_folder_var=\"\$_imf_folder\""
  eval "$_imf_out_reason_var=''"
  return 0
}

# The value _issue_context_marker_mode returns for a "{" line that does not
# match the one shape it parses. It starts with "!", which no parsed mode can
# hold, so a caller can never mistake it for a mode.
_ISSUE_CONTEXT_MARKER_MODE_INVALID="!invalid"

# _issue_context_marker_mode <out-mode-var> — read the mode form of this
# worktree's marker into <out-mode-var>.
#
# Returns 0 when the first line of the marker starts with "{". The mode is the
# value of the single "mode" key, or _ISSUE_CONTEXT_MARKER_MODE_INVALID when
# the line has any other shape. The value is not checked against the known
# modes: which modes exist is the caller's question.
#
# Returns 1, with an empty mode, when there is no marker, when it cannot be
# read, or when it holds the path form.
_issue_context_marker_mode() {
  local _imm_out_var="$1" _imm_file _imm_line
  local _imm_re='^\{[[:space:]]*"mode"[[:space:]]*:[[:space:]]*"([a-z][a-z-]*)"[[:space:]]*\}$'

  eval "$_imm_out_var=''"

  _imm_file="$(_issue_context_marker_path)" || return 1
  [ -f "$_imm_file" ] && [ -r "$_imm_file" ] || return 1
  IFS= read -r _imm_line < "$_imm_file" || _imm_line="${_imm_line:-}"
  _imm_line="${_imm_line#"${_imm_line%%[![:space:]]*}"}"
  _imm_line="${_imm_line%"${_imm_line##*[![:space:]]}"}"

  case "$_imm_line" in
    "{"*) ;; # kcov-exclude-line
    *) return 1 ;;
  esac

  if [[ "$_imm_line" =~ $_imm_re ]]; then
    eval "$_imm_out_var=\"\${BASH_REMATCH[1]}\""
  else
    eval "$_imm_out_var=\"\$_ISSUE_CONTEXT_MARKER_MODE_INVALID\""
  fi
  return 0
}
