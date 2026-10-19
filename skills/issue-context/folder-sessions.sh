#!/usr/bin/env bash
#
# folder-sessions.sh — List the sessions that claim a work folder, and say
# whether each one runs.
#
# Usage:
#   folder-sessions.sh [--others] <folder>
#   folder-sessions.sh --help
#
#   <folder>   An absolute path to an existing directory.
#   --others   Leave out the session that runs this script: the session of
#              CLAUDE_CODE_SESSION_ID, and the job of a background session
#              after a /clear.
#
# This script is the one rule that decides whether the session of a folder
# runs. resume-agent.sh, launch-agent.sh, set-work-folder.sh, and
# session-hook.sh call it, and a caller in another repository calls it too,
# so that no caller keeps its own copy of the rule. It reads and never
# writes.
#
# A session claims a folder through its session file (session-file.sh). The
# script reads each session file that names the folder, then joins it to
# `claude agents --json` (the live list) and `claude agents --json --all`
# (the live list and the ended jobs). It reads both lists, because --all
# gives an ended job and a retired row the same fields.
#
# A file joins to a job row by its job_session_id field, by the sessionId of
# a row, or by the job id of a row: the 8-character `id`, which is the first 8
# characters of the first session id of the job. A /clear gives a background
# session a new session id and keeps its job id, so the files of one job,
# before and after a /clear, give one line. An interactive session has no
# job id, so it joins by its sessionId only.
#
# Output (stdout): one line for each session, newest session file first:
#
#   <session id><TAB><job id><TAB><name><TAB><state>
#
#   session id  running or retired: the current conversation of the row.
#               ended: the first session id of the job, which
#               `claude --bg --resume` wakes with no copy and no second job
#               record; with no job, the session id of the newest file.
#   job id      the 8-character job id, or - for an interactive session and
#               for a session that no row names.
#   name        the name in the row, or - when no row names the session.
#
# No field is ever empty: bash `read` with a tab in IFS joins two adjacent
# tabs, so an empty field would shift each field after it.
#   state       running  a live row with a process or a status
#               retired  a live row with status null and pid null: a
#                        background session that has no process. A
#                        `claude --bg --resume` of it starts a copy, and
#                        `claude attach <job id>` wakes it.
#               ended    no live row
#
# No output means that no session claims the folder. The script then reads
# no list at all.
#
# Exit codes:
#   0  — the list is complete, possibly empty
#   1  — usage error (H001) or a folder that is not an existing absolute
#        directory (H002)
#   2  — the sessions cannot be read: jq is missing (H003), or
#        `claude agents --json` failed (H004). stdout is empty. A caller
#        decides what a failed check means for it.

set -euo pipefail

readonly ERR_USAGE="H001"
readonly ERR_FOLDER="H002"
readonly ERR_NO_JQ="H003"
readonly ERR_AGENTS="H004"

usage() {
  cat <<'EOF'
Usage: folder-sessions.sh [--others] <folder>
       folder-sessions.sh --help

  <folder>  Absolute path to an existing directory
  --others  Leave out the session that runs this script
  --help    Show this help message
EOF
}

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/session-file.sh"

die() {
  echo "folder-sessions $2 error: $3" >&2
  exit "$1"
}

others=0
case "${1-}" in
  --help)
    usage
    exit 0
    ;;
  --others)
    others=1
    shift
    ;;
esac
case "${1-}" in
  "")
    usage >&2
    die 1 "$ERR_USAGE" "a folder is required"
    ;;
  -*)
    die 1 "$ERR_USAGE" "unknown flag '$1'"
    ;;
esac
[ "$#" -eq 1 ] || die 1 "$ERR_USAGE" "expected one folder, got $# arguments"
case "$1" in
  /*) ;; # kcov-exclude-line
  *) die 1 "$ERR_FOLDER" "'$1' is not an absolute path" ;;
esac
[ -d "$1" ] || die 1 "$ERR_FOLDER" "'$1' is not an existing directory"
# Canonical, because set-work-folder.sh stores the folder with pwd -P, and the
# two compare as strings.
folder="$(cd "$1" && pwd -P)" || die 1 "$ERR_FOLDER" "'$1' could not be resolved"

command -v jq >/dev/null 2>&1 \
  || die 2 "$ERR_NO_JQ" "jq not found; it is required to read the session files and the claude agents list"

# No sessions directory means that no session claims any folder.
files="$(_issue_context_sessions_of_folder "$folder")" || exit 0
[ -n "$files" ] || exit 0

self_id=""
self_first=""
if [ "$others" -eq 1 ]; then
  self_id="${CLAUDE_CODE_SESSION_ID:-}"
  _issue_context_job_first_id self_first || self_first=""
  # The files of the caller go first, so a folder that only the caller
  # claims reads no list. The jq join below also leaves out a caller that
  # only a row names.
  kept=""
  while IFS=$'\t' read -r f_written f_sid f_first; do
    [ -n "$f_sid" ] || continue
    [ "$f_sid" != "$self_id" ] || continue
    if [ -n "$self_first" ]; then
      [ "${f_sid:0:8}" != "${self_first:0:8}" ] || continue
      [ "${f_first:0:8}" != "${self_first:0:8}" ] || continue
    fi
    kept="${kept}${f_written}"$'\t'"${f_sid}"$'\t'"${f_first}"$'\n'
  done <<FILES
$files
FILES
  files="$kept"
  [ -n "$files" ] || exit 0
fi

# read_list <out-var> [--all] — set <out-var> to the JSON array that
# `claude agents --json [--all]` prints. Returns 1 when the command fails or
# prints no JSON array.
read_list() {
  local _rl_out
  _rl_out="$(claude agents --json ${2:+"$2"} 2>/dev/null)" || return 1
  printf '%s' "$_rl_out" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  eval "$1=\"\$_rl_out\""
}

live=""
all=""
read_list live \
  || die 2 "$ERR_AGENTS" "claude agents --json failed, so the state of the sessions of $folder is unknown"
read_list all --all \
  || die 2 "$ERR_AGENTS" "claude agents --json --all failed, so the state of the sessions of $folder is unknown"

printf '%s\n' "$files" | jq -R -n -r \
  --argjson live "$live" --argjson all "$all" \
  --arg self_id "$self_id" --arg self_job "${self_first:0:8}" '
  # kcov-exclude-start
  def clean: tostring | gsub("[\t\n\r]"; " ");
  def jobid: if type == "string" and length >= 8 then .[0:8] else null end;
  [inputs | split("\t") | select(length >= 2 and .[1] != "")
   | {written: .[0], sid: .[1], first: (if (.[2] // "") == "" then null else .[2] end)}]
  # The job of each file: its job_session_id first, then the row with its
  # sessionId (live before ended), then the job row whose id it starts with.
  | map(. as $f
      | (if $f.first then ($f.first | jobid)
         else (first(($live[], $all[]) | select(.sessionId == $f.sid) | .id) //
               first(($live[], $all[]) | select(.id != null and .id == ($f.sid | jobid)) | .id) //
               null)
         end) as $job
      | . + {job: $job, key: (if $job then "job:" + $job else "sid:" + $f.sid end)})
  # One group for each job, in the order of its newest file.
  | reduce .[] as $f ({order: [], groups: {}};
      if .groups[$f.key] then .groups[$f.key] += [$f]
      else .order += [$f.key] | .groups[$f.key] = [$f] end)
  | .groups as $g
  | .order[] | $g[.] as $files
  | ($files[0].job) as $job
  | [$files[].sid] as $sids
  | ((if $job then first($live[] | select(.id == $job))
      else first($live[] | select(.sessionId as $s | $sids | index($s))) end) // null) as $lrow
  | ((if $job then first($all[] | select(.id == $job))
      else first($all[] | select(.sessionId as $s | $sids | index($s))) end) // null) as $arow
  | select(($self_id == "" or (($sids | index($self_id)) == null
            and ($lrow.sessionId // "") != $self_id))
           and ($self_job == "" or ($job != $self_job
                                    and ([$sids[] | jobid] | index($self_job)) == null)))
  | (if $lrow == null then "ended"
     elif $lrow.pid == null and $lrow.status == null then "retired"
     else "running" end) as $state
  | (if $state != "ended" then $lrow.sessionId
     elif $job then
       (first($files[].first | select(. != null)) //
        first($arow.sessionId | select(. != null and jobid == $job)) //
        first($sids[] | select(jobid == $job)) //
        $sids[0])
     else $sids[0] end) as $session
  | [$session, ($job // "-"),
     (($lrow.name // $arow.name // "") | clean | if . == "" then "-" else . end), $state]
  | join("\t")
' # kcov-exclude-end
