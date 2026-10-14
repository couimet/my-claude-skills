#!/usr/bin/env bash
#
# resume-agent.sh — Make the session of a topic folder run again, so the next
# round of work on the topic goes to the session that holds the earlier
# rounds.
#
# Usage:
#   resume-agent.sh <folder>
#   resume-agent.sh --help
#
#   <folder>   An absolute path, used as given, or a slug naming one directory
#              under the topic root (the launchAgentDefaultFolder setting, else
#              the root of the current repository; see topic-root.sh). The
#              folder must exist: this script never creates one.
#
# The session of a folder is found through the session files that
# set-work-folder.sh writes, one for each session, each naming the folder of
# that session. The file of the session that runs this script is skipped, so a
# person who types the skill in the folder's own session does not restart it.
# When more files remain, the newest written_at wins and stderr names the
# others.
#
# `claude agents --json` then says whether the session runs:
#
#   listed      it runs. Nothing restarts it, because `claude --bg --resume`
#               on a running session starts a copy.
#   not listed  it ended. `claude --bg --resume <session id>` wakes it with no
#               prompt, idle, under the name it was saved with. No flag is
#               passed: with a flag such as --name, Claude Code 2.1.296 starts
#               a copy under a new id instead of the session. The script then
#               reads the list again and checks that the session is there.
#
# The script sends no prompt and attaches nothing. A caller sends its own
# prompt to the printed name, and a person opens the session from the agent
# view.
#
# Output (stdout), one labelled line each:
#   Folder:   the resolved folder
#   Session:  the full session id
#   Id:       the short id, the first 8 characters of the session id
#   Name:     the name `claude agents` lists the session under
#   State:    the state `claude agents` reports, such as working, blocked,
#             idle, or done
#   Action:   restarted, or already running
#   Open:     how a person opens the session with no shell command
#
# Exit codes:
#   0  — the session runs (it ran already, or it restarted)
#   1  — error (see stderr): R001 usage, R002 folder, R003 no session file,
#        R004 `claude agents --json` failed, R005 restart failed

set -euo pipefail

readonly ERR_USAGE="R001"
readonly ERR_FOLDER="R002"
readonly ERR_NO_SESSION="R003"
readonly ERR_AGENTS="R004"
readonly ERR_RESTART="R005"

usage() {
  cat <<'EOF'
Usage: resume-agent.sh <folder>
       resume-agent.sh --help

  <folder>  Absolute path, or a slug naming one directory under the
            launchAgentDefaultFolder setting, else the repository root.
            The folder must exist.
  --help    Show this help message
EOF
}

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/issue-settings.sh"
# shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/session-file.sh"
# shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/topic-root.sh"

die() {
  echo "resume-agent $1 error: $2" >&2
  exit 1
}

# --- Parse arguments ---
case "${1-}" in
  --help)
    usage
    exit 0
    ;;
  "")
    usage >&2
    die "$ERR_USAGE" "a folder is required"
    ;;
  -*)
    die "$ERR_USAGE" "unknown flag '$1'"
    ;;
esac
[ "$#" -eq 1 ] || die "$ERR_USAGE" "expected one folder, got $# arguments"
folder="$1"

command -v jq >/dev/null 2>&1 \
  || die "$ERR_NO_SESSION" "jq not found; it is required to read the session files and the claude agents list"

# --- Resolve the folder ---
while [ "$folder" != "/" ] && [ "${folder%/}" != "$folder" ]; do
  folder="${folder%/}"
done
case "$folder" in
  /*) # kcov-exclude-line
    target="$folder"
    ;;
  */* | . | ..)
    die "$ERR_FOLDER" "'$folder' is not a topic name; pass a single name, or an absolute path"
    ;;
  *)
    root=""
    root_reason=""
    if ! _issue_context_topic_root root root_reason; then
      case "$root_reason" in
        settings)
          die "$ERR_FOLDER" "the settings file $SETTINGS_FILE could not be read, so launchAgentDefaultFolder is unknown; fix the file, or pass an absolute path as the folder" ;;
        relative | missing)
          die "$ERR_FOLDER" "launchAgentDefaultFolder in $SETTINGS_FILE is '$SETTINGS_LAUNCH_AGENT_DEFAULT_FOLDER', which is not an absolute path to an existing directory; fix the setting, or pass an absolute path as the folder" ;;
        *)
          die "$ERR_FOLDER" "not inside a git repository, so a slug has no root to resolve against; set launchAgentDefaultFolder or pass an absolute path instead" ;;
      esac
    fi
    target="$root/$folder"
    ;;
esac
[ -d "$target" ] || die "$ERR_FOLDER" "'$target' is not an existing directory; this skill never creates a folder"
# Canonical, because set-work-folder.sh stores the folder with pwd -P, and the
# two must compare as strings.
folder_abs="$({ cd "$target" && pwd -P; } 2>/dev/null)" \
  || die "$ERR_FOLDER" "'$target' could not be resolved"
folder_name="${folder_abs##*/}"

# --- Find the session of the folder ---
sessions_dir="$(_issue_context_sessions_dir)" \
  || die "$ERR_NO_SESSION" "could not resolve the sessions directory from the settings path"

# One "<written_at><TAB><session_id>" line for each session file that names
# the folder, newest first. A file that does not parse is skipped: it names no
# folder this script can trust.
matches=""
if [ -d "$sessions_dir" ]; then
  for file in "$sessions_dir"/*.json; do
    [ -f "$file" ] || continue
    line="$(jq -r --arg f "$folder_abs" \
      'select(type == "object" and .folder == $f and (.session_id | type == "string"))
       | "\(.written_at // "")\t\(.session_id)"' "$file" 2>/dev/null || true)"
    [ -n "$line" ] || continue
    matches="${matches}${line}"$'\n'
  done
fi
matches="$(printf '%s' "$matches" | LC_ALL=C sort -r)"

self_id="${CLAUDE_CODE_SESSION_ID:-}"
session_id=""
others=()
while IFS=$'\t' read -r _written sid; do
  [ -n "$sid" ] || continue
  [ "$sid" != "$self_id" ] || continue
  if [ -z "$session_id" ]; then
    session_id="$sid"
  else
    others+=("$sid")
  fi
done <<EOF
$matches
EOF

[ -n "$session_id" ] \
  || die "$ERR_NO_SESSION" "no session other than this one has its working files in $folder_abs, so there is no session to resume; start one with /launch-agent"
# The id reaches a command line and a jq filter, so it must be one plain token.
[[ "$session_id" =~ ^[A-Za-z0-9_-]+$ ]] \
  || die "$ERR_NO_SESSION" "the session file for $folder_abs holds the session id '$session_id', which is not a valid id"

for other in ${others[@]+"${others[@]}"}; do
  echo "resume-agent: another session also used this folder: $other (not resumed; the newest one wins)" >&2
done

# --- Read the live sessions ---
# agents_entry — print the `claude agents --json` entry of the session as one
# JSON line, or nothing when it is not listed. Returns 1 when the command
# fails or prints no JSON array.
agents_entry() {
  local list
  list="$(claude agents --json 2>/dev/null)" || return 1
  printf '%s' "$list" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$list" | jq -c --arg id "$session_id" \
    '[.[] | select(.sessionId == $id)] | first // empty'
}

entry="$(agents_entry)" \
  || die "$ERR_AGENTS" "claude agents --json failed, so the state of session $session_id is unknown; nothing was restarted"

if [ -n "$entry" ]; then
  action="already running"
else
  # No prompt, and no flag. See the header for why --name is not passed.
  restart_output="$(claude --bg --resume "$session_id" 2>&1)" || {
    {
      echo "resume-agent $ERR_RESTART error: claude --bg --resume $session_id failed:"
      printf '%s\n' "$restart_output" | sed 's/^/  /'
    } >&2 # kcov-exclude-line
    exit 1
  }
  case "$restart_output" in
    *"started a copy"*)
      {
        echo "resume-agent $ERR_RESTART error: claude started a copy of session $session_id rather than the session itself. Stop the copy with claude stop <copy id>:"
        printf '%s\n' "$restart_output" | sed 's/^/  /'
      } >&2 # kcov-exclude-line
      exit 1
      ;;
  esac
  entry="$(agents_entry)" \
    || die "$ERR_AGENTS" "claude agents --json failed after the restart, so it is not known whether session $session_id runs"
  [ -n "$entry" ] \
    || die "$ERR_RESTART" "claude --bg --resume $session_id returned, but claude agents does not list the session"
  action="restarted"
fi

short_id="$(printf '%s' "$entry" | jq -r '.id // empty')"
[ -n "$short_id" ] || short_id="${session_id:0:8}"
name="$(printf '%s' "$entry" | jq -r '.name // empty')"
state="$(printf '%s' "$entry" | jq -r '.state // .status // "unknown"')"

if [ "$name" != "$folder_name" ]; then
  echo "resume-agent: the session runs under the name '${name:-<none>}', not '$folder_name'; address it by its id, $short_id" >&2
fi
open_name="${name:-$short_id}"

printf 'Folder: %s\n' "$folder_abs"
printf 'Session: %s\n' "$session_id"
printf 'Id: %s\n' "$short_id"
printf 'Name: %s\n' "${name:-<none>}"
printf 'State: %s\n' "$state"
printf 'Action: %s\n' "$action"
printf 'Open: in the agent view (claude agents), press Ctrl+F, type %s, and press Enter\n' "$open_name"
