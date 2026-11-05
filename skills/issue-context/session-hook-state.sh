#!/usr/bin/env bash
#
# session-hook-state.sh — Say whether the session hook (session-hook.sh) is
# sure to run at UserPromptSubmit when a session starts in a directory.
#
# Usage:
#   session-hook-state.sh [--project <dir>]
#   session-hook-state.sh --help
#
#   --project <dir>  The directory where the session starts. Its
#                    .claude/settings.json and .claude/settings.local.json
#                    can turn all hooks off (see disableAllHooks below).
#
# The hook gives a session the name of its folder at its first prompt. A
# caller that restarts a session with a prompt of its own, and no /rename,
# needs that hook, else the session takes its name from the text of the
# prompt. So resume-agent.sh asks this script before it chooses the restart.
#
# Contract (PR 313): best effort, on strong evidence only. Claude Code builds
# its hook configuration from more inputs than a script can model, so the
# script reads the inputs below and no other. Each other input gives none,
# or is a limit of this list. none is the safe answer: the caller restarts
# with /rename and sends the prompt itself, which costs one message. A wrong
# settings costs a session named from its prompt, and resume-agent.sh then
# prints its Rename line, so a wrong guess is never silent.
#
# The inputs:
#
#   - The hook entry: a UserPromptSubmit entry of the hook in the user
#     settings file, SESSION_HOOK_STATE_SETTINGS (default
#     ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json), the form that install.sh
#     writes. The entry test is the one of install.sh: session-hook-rule.jq,
#     beside this script.
#   - disableAllHooks, from the user settings file, then, with --project,
#     <dir>/.claude/settings.json and <dir>/.claude/settings.local.json, the
#     order of Claude Code. The last file that sets it to a boolean decides,
#     and true gives none.
#   - The managed policy settings: when a managed settings file exists, the
#     state is none, with no parse. The paths are
#     SESSION_HOOK_STATE_MANAGED (default: the macOS path
#     /Library/Application Support/ClaudeCode/managed-settings.json and the
#     Linux path /etc/claude-code/managed-settings.json).
#   - A file that is missing, or is not a JSON object, sets nothing.
#
# The limits, which give none or are not seen: a plugin install (its hook
# entry is in hooks/hooks.json, and its install state is not a documented
# file), a hook entry in the project or local settings, --plugin-dir, the
# saved --settings of a job, the settings of a parent directory (a session
# reads its project settings from the directory it starts in only; see the
# header of resume-agent.sh), and a hook script that cannot run.
#
# Output (stdout): one line, one value of an enum, so a new value adds with
# no reader change:
#
#   settings  the hook entry is in the user settings, no read file sets
#             disableAllHooks to true, and no managed settings file exists
#   none      each other case
#
# Exit codes:
#   0  — the state is printed
#   1  — usage error (K001), or jq is missing (K002)

set -euo pipefail

readonly ERR_USAGE="K001"
readonly ERR_NO_JQ="K002"

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SETTINGS="${SESSION_HOOK_STATE_SETTINGS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json}"

project=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help)
      # The header, from its third line to the first line that is not a
      # comment.
      awk 'NR > 2 && !/^#/ { exit } NR > 2 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    --project)
      [ "$#" -ge 2 ] && [ -n "$2" ] \
        || { echo "session-hook-state $ERR_USAGE error: --project requires a directory" >&2; exit 1; }
      project="$2"
      shift 2
      ;;
    *)
      echo "session-hook-state $ERR_USAGE error: unexpected argument '$1'" >&2
      exit 1
      ;;
  esac
done

command -v jq >/dev/null 2>&1 \
  || { echo "session-hook-state $ERR_NO_JQ error: jq not found; it is required to read $SETTINGS" >&2; exit 1; }

# managed_present — 0 when one of the managed settings files exists. See
# the header: its keys are not parsed, so its presence alone gives none.
managed_present() {
  local m
  local -a paths=("/Library/Application Support/ClaudeCode/managed-settings.json" "/etc/claude-code/managed-settings.json")
  [ -z "${SESSION_HOOK_STATE_MANAGED+set}" ] || paths=("$SESSION_HOOK_STATE_MANAGED")
  for m in "${paths[@]}"; do
    [ -n "$m" ] && [ -e "$m" ] && return 0
  done
  return 1
}

# disabled_in <file> — print true or false when <file> is a JSON object that
# sets disableAllHooks to a boolean, and nothing otherwise.
disabled_in() {
  [ -r "$1" ] || return 0
  jq -r 'if type == "object" and (.disableAllHooks | type == "boolean") then .disableAllHooks else empty end' "$1" 2>/dev/null || true
}

state="none"
if ! managed_present && [ -r "$SETTINGS" ] \
    && jq -e "$(cat "$_self_dir/session-hook-rule.jq") type == \"object\" and ([(.hooks.UserPromptSubmit // [])[]?.hooks[]? | select(ours)] | length) > 0" "$SETTINGS" >/dev/null 2>&1; then
  state="settings"
  disabled=""
  for f in "$SETTINGS" ${project:+"$project/.claude/settings.json" "$project/.claude/settings.local.json"}; do
    value="$(disabled_in "$f")"
    [ -z "$value" ] || disabled="$value"
  done
  [ "$disabled" != "true" ] || state="none"
fi
printf '%s\n' "$state"
