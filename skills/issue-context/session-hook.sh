#!/usr/bin/env bash
#
# session-hook.sh — The Claude Code hook that keeps the work folder of a
# session after a /clear, warns a resumed session when another session holds
# its work folder, and keeps the session name equal to its folder name.
#
# Usage: Claude Code runs this script with one JSON object on stdin. It has
# no arguments.
#
# Install: hooks/hooks.json names this script for the plugin, and install.sh
# adds the same entry to ~/.claude/settings.json when the user agrees. Both
# limit the calls with matchers: SessionEnd with the reason clear, and
# SessionStart with the source clear or resume. UserPromptSubmit has no
# matcher, so it runs at each prompt, and the cheap checks come first. The
# script checks the event again, because a user can write the settings entry
# by hand.
#
# The four events (see docs/ADR/006-claude-code-hooks.md):
#
#   SessionEnd, reason clear
#       Read the work folder of the old session id, and write it to a
#       handoff file, <dirname SETTINGS_FILE>/clear-handoff/<pid>.json. The
#       pid is CLAUDE_PID, else PPID, and only a number. A /clear fires this
#       event and the next one in the same Claude Code process, so the pid
#       links the two calls.
#   SessionStart, source clear
#       When no session file names the new session id itself, take the folder
#       from the handoff file of this process, or else from the session file
#       that the reader finds through the job state of a background session.
#       Then write the session file of the new id with set-work-folder.sh. A
#       handoff file older than SESSION_HOOK_HANDOFF_MAX_AGE seconds (default
#       300) is not used, because a process id can be used again. The
#       handoff file is removed after the read, used or not. A title record
#       of the old id (see UserPromptSubmit) moves to the new id with the
#       folder, so a name that the user chose stays a choice.
#   SessionStart, source resume
#       When folder-sessions.sh shows another running or retired session in
#       the work folder of this session, print additionalContext that names
#       that session, tells this session not to write working files in the
#       folder, and gives the /resume-agent command.
#   UserPromptSubmit
#       Keep the session title equal to the folder name of the work folder.
#       The input holds the title as session_title, and the transcript at
#       transcript_path holds ai-title and custom-title entries. A title that
#       a hook sets writes a custom-title entry, as a typed /rename does, so
#       the hook keeps its own title record,
#       <dirname SETTINGS_FILE>/session-titles/<session id>.json, with the
#       fields "set" (the last title it set), "warned" (the last title it
#       warned about), and "wanted" (the name that rename-agent.sh asked for).
#       In this order:
#       - no session file: nothing.
#       - "wanted" is set: set the title to it with no warning, write "set",
#         and remove "wanted" and "warned".
#       - the title is the folder name, or the title that the hook set:
#         nothing.
#       - a drift (no title, or the newest title entry is an ai-title): set
#         the title to the folder name and write "set". When another running
#         or retired session holds the folder, set nothing, because two
#         sessions with one name make a send by name reach either one; give
#         additionalContext that names that session, once for each title.
#       - else the user chose the title. Keep it, and give additionalContext
#         with the line of find-agent.sh --check, once for each title. That
#         line gives /launch-agent first when the title is the folder name of
#         another existing folder, and /rename-agent first otherwise.
#
# Output: for a resume that finds another session, or a prompt that sets a
# title or warns, one JSON object on stdout, the form that Claude Code reads
# for that event (hookSpecificOutput.sessionTitle for a title). Each other
# path prints nothing on stdout.
#
# Exit codes: always 0. A hook that fails can stop or disturb the start of a
# session, and a missing folder is less harmful than a session that does not
# start. So on an error the script prints at most one stderr line, prefixed
# with "session-hook:", and exits 0. The script is idempotent, because a user
# can install the hook twice (the plugin and the settings entry).

set -uo pipefail

# Each exit is 0, also an abort from set -u. See the header.
trap 'exit 0' EXIT

# warn <message> — print one stderr line, and stop with exit 0.
warn() {
  echo "session-hook: $*" >&2
  exit 0
}

command -v jq >/dev/null 2>&1 || warn "jq not found, so the hook did nothing"

# Parse the input once. The first field is the case, the second field is the
# session id when it is one plain token, else empty. A path that does nothing
# stops here, before any file is sourced.
input="$(cat)"
parsed="$(printf '%s' "$input" | jq -r '
  # kcov-exclude-start
  if type != "object" then "invalid"
  else
    (if .hook_event_name == "SessionEnd" and .reason == "clear" then "end-clear"
     elif .hook_event_name == "SessionStart" and .source == "clear" then "start-clear"
     elif .hook_event_name == "SessionStart" and .source == "resume" then "start-resume"
     elif .hook_event_name == "UserPromptSubmit" then "prompt"
     else "other" end)
    + "\t"
    + (if (.session_id | type == "string") and (.session_id | test("^[A-Za-z0-9_-]+$"))
       then .session_id else "" end)
  end
  # kcov-exclude-end
' 2>/dev/null)" || parsed="invalid"

event="${parsed%%$'\t'*}"
session_id=""
case "$parsed" in
  *$'\t'*) session_id="${parsed#*$'\t'}" ;;
esac

case "$event" in
  end-clear | start-clear | start-resume | prompt) ;;
  other) exit 0 ;;
  *) warn "the input is not one JSON object, so the hook did nothing" ;;
esac
[ -n "$session_id" ] \
  || warn "the input has no session_id that can be a file name, so the hook did nothing"

# The helpers key on this variable.
export CLAUDE_CODE_SESSION_ID="$session_id"

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# A warning about the settings file is not the business of this hook, and it
# could be more than one line.
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh" 2>/dev/null
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/session-file.sh"

# handoff_file — print the path of the handoff file of this process. Returns
# 1 when there is no settings path or no numeric process id.
handoff_file() {
  local pid="${CLAUDE_PID:-}" dir
  case "$pid" in
    '' | *[!0-9]*) pid="${PPID:-}" ;;
  esac
  case "$pid" in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ -n "${SETTINGS_FILE:-}" ] || return 1
  # Beside the sessions directory, so MY_CLAUDE_SKILLS_CONFIG moves both.
  case "$SETTINGS_FILE" in
    */*) dir="${SETTINGS_FILE%/*}/clear-handoff" ;;
    *) dir="./clear-handoff" ;;
  esac
  printf '%s/%s.json\n' "$dir" "$pid"
}

# --- SessionEnd, reason clear ---
if [ "$event" = "end-clear" ]; then
  folder=""
  reason=""
  if ! _issue_context_session_file_read folder reason; then
    [ "$reason" = "none" ] && exit 0
    warn "the session file of $session_id could not be read ($reason), so its work folder does not carry over the /clear"
  fi
  handoff="$(handoff_file)" \
    || warn "no process id, so the work folder $folder does not carry over the /clear"
  mkdir -p "${handoff%/*}" 2>/dev/null \
    || warn "could not create ${handoff%/*}, so the work folder $folder does not carry over the /clear"
  # Written in a temporary file and renamed, so a reader sees no half file.
  tmp="$(mktemp "${handoff%/*}/.tmp-XXXXXX" 2>/dev/null)" \
    || warn "could not write in ${handoff%/*}, so the work folder $folder does not carry over the /clear"
  if ! jq -n --arg folder "$folder" --arg session_id "$session_id" \
      --argjson written_at "$(date +%s)" \
      '{folder: $folder, session_id: $session_id, written_at: $written_at}' \
      > "$tmp" 2>/dev/null \
    || ! mv -f "$tmp" "$handoff" 2>/dev/null; then
    rm -f "$tmp"
    warn "could not write $handoff, so the work folder $folder does not carry over the /clear"
  fi
  exit 0
fi

# --- SessionStart, source clear ---
if [ "$event" = "start-clear" ]; then
  handoff="$(handoff_file)" || handoff=""

  # A file under the new id itself means that the folder is already set,
  # for example by a second install of this hook. A file that the reader
  # finds through the job state names the first id, so it does not count:
  # the new id still gets its own file.
  matches=()
  if _issue_context_session_file_matches matches; then
    for f in ${matches[@]+"${matches[@]}"}; do
      case "${f##*/}" in
        "$session_id.json" | "$session_id--"*.json)
          [ -z "$handoff" ] || rm -f "$handoff"
          exit 0
          ;;
      esac
    done
  fi

  folder=""
  old_id=""
  if [ -n "$handoff" ] && [ -f "$handoff" ]; then
    max_age="${SESSION_HOOK_HANDOFF_MAX_AGE:-300}"
    case "$max_age" in
      '' | *[!0-9]*) max_age=300 ;;
    esac
    written_at="$(jq -r 'if type == "object" and (.written_at | type == "number")
                         then .written_at | floor else empty end' "$handoff" 2>/dev/null)" \
      || written_at=""
    if [ -n "$written_at" ]; then
      age=$(($(date +%s) - written_at))
      if [ "$age" -ge 0 ] && [ "$age" -le "$max_age" ]; then
        folder="$(jq -r 'if (.folder | type == "string") then .folder else empty end' \
          "$handoff" 2>/dev/null)" || folder=""
        old_id="$(jq -r '.session_id | strings | select(test("^[A-Za-z0-9_-]+$"))' \
          "$handoff" 2>/dev/null)" || old_id=""
      fi
    fi
    rm -f "$handoff"
  fi

  if [ -z "$folder" ]; then
    reason=""
    _issue_context_session_file_read folder reason || exit 0
  fi

  [ -d "$folder" ] \
    || warn "the work folder $folder of the session before the /clear does not exist, so no folder is set for this session"
  "$_self_dir/set-work-folder.sh" "$folder" >/dev/null 2>&1 \
    || warn "could not set the work folder after the /clear; run /set-work-folder $folder"
  # The title record goes with the folder. A failed move only loses the
  # record, so the next prompt decides from the transcript.
  if [ -n "$old_id" ] && [ "$old_id" != "$session_id" ] && titles="$(_issue_context_titles_dir)" \
      && [ -f "$titles/$old_id.json" ] && [ ! -e "$titles/$session_id.json" ]; then
    mv -f "$titles/$old_id.json" "$titles/$session_id.json" 2>/dev/null || true
  fi
  exit 0
fi

# --- UserPromptSubmit ---
if [ "$event" = "prompt" ]; then
  folder=""
  reason=""
  _issue_context_session_file_read folder reason || exit 0
  folder_name="${folder##*/}"
  title="$(printf '%s' "$input" | jq -r '.session_title | strings' 2>/dev/null)" || title=""
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path | strings' 2>/dev/null)" || transcript=""

  titles="$(_issue_context_titles_dir)" || warn "no settings path, so the session name was not checked"
  record="$titles/$session_id.json"
  rec="{}"
  if [ -f "$record" ] && jq -e 'type == "object"' "$record" >/dev/null 2>&1; then
    rec="$(cat "$record")"
  fi
  rec_field() { printf '%s' "$rec" | jq -r --arg k "$1" '.[$k] | strings'; }

  # write_record <jq filter> <title> — apply <jq filter>, which reads <title>
  # as $t, to the record, through a temporary file and a rename.
  write_record() {
    local tmp
    mkdir -p "$titles" 2>/dev/null || return 1
    tmp="$(mktemp "$titles/.tmp-XXXXXX" 2>/dev/null)" || return 1
    if printf '%s' "$rec" | jq --arg t "$2" "$1" > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$record" 2>/dev/null; then
      return 0
    fi
    rm -f "$tmp"
    return 1
  }

  # set_title <title> — print the output that sets the title, and record it.
  set_title() {
    # shellcheck disable=SC2016 # a jq program: $t is a jq variable
    write_record 'del(.wanted, .warned) | .set = $t' "$1" \
      || warn "could not write $record, so the title was not set"
    jq -n --arg t "$1" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", sessionTitle: $t}}' \
      || warn "could not write the session title"
    exit 0
  }

  # warn_once <context> — print <context> once for each title, and record it.
  warn_once() {
    [ "$(rec_field warned)" != "$title" ] || exit 0
    # shellcheck disable=SC2016 # a jq program: $t is a jq variable
    write_record '.warned = $t' "$title" \
      || warn "could not write $record, so the warning was not given"
    jq -n --arg context "$1" \
      '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $context}}' \
      || warn "could not write the warning about the session name"
    exit 0
  }

  wanted="$(rec_field wanted)"
  [ -z "$wanted" ] || set_title "$wanted"
  [ "$title" != "$folder_name" ] || exit 0
  [ -z "$title" ] || [ "$title" != "$(rec_field set)" ] || exit 0

  newest=""
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    newest="$(grep -E '"type": ?"(ai|custom)-title"' "$transcript" 2>/dev/null | tail -n 1 \
      | jq -r '.type | strings' 2>/dev/null)" || newest=""
  fi

  if [ -z "$title" ] || [ "$newest" = "ai-title" ]; then
    # A drift. Another holder would get the same name, so it warns instead.
    holders=""
    if [ -d "$folder" ] \
        && check_out="$("$_self_dir/folder-sessions.sh" --others "$folder" 2>/dev/null)"; then
      while IFS=$'\t' read -r h_sid h_job h_name h_state; do
        case "$h_state" in
          running | retired)
            holders="${holders}- session $h_sid, job $h_job, name $h_name, state $h_state"$'\n'
            ;;
        esac
      done <<HOLDERS
$check_out
HOLDERS
    fi
    [ -n "$holders" ] || set_title "$folder_name"
    warn_once "This session has a new name, '$title', in place of its folder name $folder_name. The hook did not give it the folder name back, because another session holds the work folder $folder of this session, and two sessions with one name make a send by name reach either one:
${holders}Give the user this command, which says what to do, and do not run it yourself: /find-agent $folder"
  fi

  check_rc=0
  check_line="$("$_self_dir/find-agent.sh" --check --title "$title" 2>/dev/null)" || check_rc=$?
  [ "$check_rc" -eq 1 ] && [ -n "$check_line" ] || exit 0
  warn_once "$check_line. Give the user these commands, and run none of them: the user decides."
fi

# --- SessionStart, source resume ---
folder=""
reason=""
_issue_context_session_file_read folder reason || exit 0
[ -d "$folder" ] || exit 0

check_rc=0
check_out="$("$_self_dir/folder-sessions.sh" --others "$folder" 2>&1)" || check_rc=$?
if [ "$check_rc" -ne 0 ]; then
  check_why="${check_out##*$'\n'}"
  check_why="${check_why#*error: }"
  warn "could not check whether another session holds $folder (${check_why:-no reason given})"
fi

holders=""
while IFS=$'\t' read -r h_sid h_job h_name h_state; do
  case "$h_state" in
    running | retired)
      holders="${holders}- session $h_sid, job $h_job, name $h_name, state $h_state"$'\n'
      ;;
  esac
done <<HOLDERS
$check_out
HOLDERS
[ -n "$holders" ] || exit 0

context="Another session holds the work folder $folder of this session:
${holders}Two sessions in one work folder each see only half of the work. Do not write working files in this folder from this session. Give the user this command, so that the work continues in the session that holds the folder: /resume-agent $folder"

jq -n --arg context "$context" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}}' \
  || warn "could not write the warning about the other session of $folder"
