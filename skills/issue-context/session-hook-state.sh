#!/usr/bin/env bash
#
# session-hook-state.sh — Say whether the session hook (session-hook.sh) runs
# at UserPromptSubmit on this machine, and through which install.
#
# Usage:
#   session-hook-state.sh
#   session-hook-state.sh --help
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
# Output (stdout): one line, one value of an enum, so a new install form adds
# a value and no reader changes:
#
#   settings  a UserPromptSubmit entry of the settings file runs the hook
#   plugin    no such entry, but the my-claude-skills plugin is enabled
#   none      neither, or the settings file is missing or not JSON
#
# Exit codes:
#   0  — the state is printed
#   1  — usage error (K001), or jq is missing (K002)

set -euo pipefail

readonly ERR_USAGE="K001"
readonly ERR_NO_JQ="K002"

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SETTINGS="${SESSION_HOOK_STATE_SETTINGS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json}"

case "${1-}" in
  "") ;;
  --help)
    sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "session-hook-state $ERR_USAGE error: unexpected argument '$1'" >&2
    exit 1
    ;;
esac

command -v jq >/dev/null 2>&1 \
  || { echo "session-hook-state $ERR_NO_JQ error: jq not found; it is required to read $SETTINGS" >&2; exit 1; }

state="none"
if [ -r "$SETTINGS" ]; then
  state="$(jq -r "$(cat "$_self_dir/session-hook-rule.jq")
    if type != \"object\" then \"none\"
    elif ([(.hooks.UserPromptSubmit // [])[]?.hooks[]? | select(ours)] | length) > 0 then \"settings\"
    elif ((.enabledPlugins // {}) | to_entries | any((.key | startswith(\"my-claude-skills@\")) and .value == true)) then \"plugin\"
    else \"none\" end" "$SETTINGS" 2>/dev/null)" || state="none"
fi
case "$state" in
  settings | plugin | none) ;;
  *) state="none" ;;
esac
printf '%s\n' "$state"
