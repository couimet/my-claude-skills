#!/usr/bin/env bash
#
# rename-agent.sh — Ask for a new name for the current session. The session
# hook gives the session that name at its next prompt.
#
# Usage:
#   rename-agent.sh [name]
#   rename-agent.sh --help
#
#   [name]  The name to ask for. Several words join with one space. Without
#           it, the name is the folder name of the bound folder: the last
#           part of the folder in the session file of this session.
#
# Only a person types /rename, and Claude Code has no command line option
# that renames a running session. A UserPromptSubmit hook can set the title
# through hookSpecificOutput.sessionTitle (docs/ADR/006-claude-code-hooks.md).
# So this script writes the name in the "wanted" field of the title record of
# the session, <dirname SETTINGS_FILE>/session-titles/<session id>.json
# (_issue_context_titles_dir in session-file.sh), and keeps the other fields.
# At the next prompt, session-hook.sh sets the title, removes "wanted", and
# gives no warning about that name.
#
# The script writes only the record of CLAUDE_CODE_SESSION_ID. It never
# renames another session, and it runs no claude command.
#
# Output (stdout): one line, "The name <name> applies at your next prompt."
#
# Exit codes:
#   0  — the name is recorded
#   1  — error (see stderr): N001 usage or a name that cannot be a title, N002
#        no session id, N003 no name and no session file, N004 no jq, N005 the
#        record could not be written

set -euo pipefail

readonly ERR_USAGE="N001"
readonly ERR_NO_SESSION="N002"
readonly ERR_NO_NAME="N003"
readonly ERR_NO_JQ="N004"
readonly ERR_WRITE="N005"

usage() {
  cat <<'EOF'
Usage: rename-agent.sh [name]
       rename-agent.sh --help

  [name]  The name to ask for (default: the folder name of the bound folder)
  --help  Show this help message
EOF
}

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh" 2>/dev/null
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/session-file.sh"

die() {
  echo "rename-agent $1 error: $2" >&2
  exit 1
}

case "${1-}" in
  --help)
    usage
    exit 0
    ;;
  -*) die "$ERR_USAGE" "unknown flag '$1'" ;;
esac
name="$*"
case "$name" in
  *$'\n'* | *$'\r'* | *$'\t'*) die "$ERR_USAGE" "the name holds a line break or a tab, so it cannot be a session title" ;;
esac

_issue_context_session_id_ok \
  || die "$ERR_NO_SESSION" "CLAUDE_CODE_SESSION_ID is not set or cannot be a file name, so there is no current session to rename"
command -v jq >/dev/null 2>&1 || die "$ERR_NO_JQ" "jq not found; it is required to write the title record"

if [ -z "$name" ]; then
  folder=""
  reason=""
  if ! _issue_context_session_file_read folder reason; then
    [ "$reason" != "none" ] \
      || die "$ERR_NO_NAME" "this session has no session file, so it has no folder name; give a name, or bind a folder first with /launch-agent \"<folder>\" or /set-work-folder \"<folder>\""
    die "$ERR_NO_NAME" "the session file of this session could not be read ($reason), so it has no folder name; give a name"
  fi
  name="${folder##*/}"
fi

titles_dir="$(_issue_context_titles_dir)" \
  || die "$ERR_WRITE" "could not resolve the title records directory from the settings path"
mkdir -p "$titles_dir" 2>/dev/null || die "$ERR_WRITE" "could not create $titles_dir"
record="$titles_dir/$CLAUDE_CODE_SESSION_ID.json"

# A record that is not a JSON object holds nothing to keep.
old="{}"
if [ -f "$record" ] && jq -e 'type == "object"' "$record" >/dev/null 2>&1; then
  old="$(cat "$record")"
fi
# Written in a temporary file and renamed, so the hook never reads half a file.
tmp="$(mktemp "$titles_dir/.tmp-XXXXXX" 2>/dev/null)" || die "$ERR_WRITE" "could not write in $titles_dir"
trap 'rm -f "$tmp"' EXIT
if ! printf '%s' "$old" | jq --arg name "$name" '.wanted = $name' > "$tmp" 2>/dev/null \
    || ! mv -f "$tmp" "$record" 2>/dev/null; then
  die "$ERR_WRITE" "could not write $record"
fi

printf 'The name %s applies at your next prompt.\n' "$name"
