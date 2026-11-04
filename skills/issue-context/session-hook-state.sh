#!/usr/bin/env bash
#
# session-hook-state.sh — Say whether the session hook (session-hook.sh) runs
# at UserPromptSubmit on this machine, and through which install.
#
# Usage:
#   session-hook-state.sh [--project <dir>]
#   session-hook-state.sh --help
#
#   --project <dir>  The directory where the session runs. Its
#                    .claude/settings.json and .claude/settings.local.json
#                    can turn all hooks off (see disableAllHooks below).
#
# The hook gives a session the name of its folder at its first prompt. A
# caller that restarts a session with a prompt of its own, and no /rename,
# needs that hook, else the session takes its name from the text of the
# prompt. So resume-agent.sh asks this script before it chooses the restart.
#
# The script reads the user settings file,
# SESSION_HOOK_STATE_SETTINGS (default ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json).
# The entry test is the one of install.sh: session-hook-rule.jq, beside this
# script. A plugin install ships the hook in hooks/hooks.json, so an enabled
# plugin named my-claude-skills (a key "my-claude-skills@<marketplace>" in
# enabledPlugins, with the value true) counts too.
#
# disableAllHooks turns each hook off. The script reads it from the user
# settings file, then from <dir>/.claude/settings.json, then from
# <dir>/.claude/settings.local.json, the order of Claude Code: a later file
# that sets the key overrides an earlier one. A file that is missing, is not
# JSON, or does not set the key changes nothing. When the effective value is
# true, the state is none. The managed policy settings are not read.
#
# Output (stdout): one line, one value of an enum, so a new install form adds
# a value and no reader changes:
#
#   settings  a UserPromptSubmit entry of the settings file runs the hook
#   plugin    no such entry, but the my-claude-skills plugin is enabled
#   none      neither, the settings file is missing or not JSON, or
#             disableAllHooks is true
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

state="none"
if [ -r "$SETTINGS" ]; then
  state="$(jq -r "$(cat "$_self_dir/session-hook-rule.jq") # kcov-exclude-start
    if type != \"object\" then \"none\"
    elif ([(.hooks.UserPromptSubmit // [])[]?.hooks[]? | select(ours)] | length) > 0 then \"settings\"
    elif ((.enabledPlugins // {}) | to_entries | any((.key | startswith(\"my-claude-skills@\")) and .value == true)) then \"plugin\"
    # kcov-exclude-end
    else \"none\" end" "$SETTINGS" 2>/dev/null)" || state="none"
fi

# disabled_in <file> — print true or false when <file> sets disableAllHooks
# to a boolean, and nothing otherwise.
disabled_in() {
  [ -r "$1" ] || return 0
  jq -r 'if type == "object" and (.disableAllHooks | type == "boolean") then .disableAllHooks else empty end' "$1" 2>/dev/null || true
}

if [ "$state" != "none" ]; then
  disabled=""
  for f in "$SETTINGS" ${project:+"$project/.claude/settings.json" "$project/.claude/settings.local.json"}; do
    value="$(disabled_in "$f")"
    [ -z "$value" ] || disabled="$value"
  done
  [ "$disabled" != "true" ] || state="none"
fi
printf '%s\n' "$state"
