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
# SESSION_HOOK_STATE_SETTINGS (default ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json),
# then, with --project, <dir>/.claude/settings.json and
# <dir>/.claude/settings.local.json, the order of Claude Code. A file that is
# missing or is not a JSON object changes nothing. The managed policy
# settings are not read. From the files:
#
#   - A UserPromptSubmit entry of the hook in any file runs the hook. The
#     entry test is the one of install.sh: session-hook-rule.jq, beside this
#     script.
#   - A plugin install ships the hook in hooks/hooks.json. The keys
#     "my-claude-skills@<marketplace>" of enabledPlugins merge key by key, so
#     a later file overrides each key of an earlier one, and a true key at
#     the end means the plugin is enabled.
#   - disableAllHooks turns each hook off. The last file that sets it to a
#     boolean decides, and true gives none.
#
# Output (stdout): one line, one value of an enum, so a new install form adds
# a value and no reader changes:
#
#   settings  a UserPromptSubmit entry of one of the files runs the hook
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

# summary_of <file> — print one JSON object with the three facts of <file>:
# a hook entry, the my-claude-skills@* keys of enabledPlugins with a boolean
# value, and disableAllHooks when it is a boolean. Print nothing when the file
# is missing or is not a JSON object, so it changes nothing.
rule="$(cat "$_self_dir/session-hook-rule.jq")"
summary_of() {
  [ -r "$1" ] || return 0
  jq -c "$rule"' # kcov-exclude-start
    if type != "object" then empty else
      {hook: (([(.hooks.UserPromptSubmit // [])[]?.hooks[]? | select(ours)] | length) > 0),
       plugins: ((.enabledPlugins // {})
                 | if type == "object" then with_entries(select((.key | startswith("my-claude-skills@")) and (.value | type == "boolean"))) else {} end),
       disable: (.disableAllHooks | if type == "boolean" then . else null end)}
    end' "$1" 2>/dev/null || true # kcov-exclude-end
}

# The files in the order of Claude Code: a later file overrides an earlier
# one. See the header.
summaries=""
for f in "$SETTINGS" ${project:+"$project/.claude/settings.json" "$project/.claude/settings.local.json"}; do
  one="$(summary_of "$f")"
  [ -z "$one" ] || summaries="${summaries}${one}"$'\n'
done
state="$(printf '%s' "$summaries" | jq -r -s ' # kcov-exclude-start
  reduce .[] as $s ({hook: false, plugins: {}, disable: null};
    .hook = (.hook or $s.hook)
    | .plugins += $s.plugins
    | .disable = (if $s.disable == null then .disable else $s.disable end))
  | if .disable == true then "none"
    elif .hook then "settings"
    elif (.plugins | any(.[]; . == true)) then "plugin"
    else "none" end
  # kcov-exclude-end
' 2>/dev/null)" || state="none"
[ -n "$state" ] || state="none"
printf '%s\n' "$state"
