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
# A session claims a folder in one of two tiers, in the order of
# work-folder.sh:
#
#   session   its session file (session-file.sh) names the folder.
#   worktree  it has no session file, and the CLAUDE_WORK_FOLDER marker
#             (marker-file.sh) of the worktree of its cwd names the folder.
#             A session file that names another folder wins over the marker.
#             A marker in the mode form names no folder.
#
# The script reads each session file that names the folder, then joins it to
# `claude agents --json` (the live list) and `claude agents --json --all`
# (the live list and the ended jobs). It reads both lists, because --all
# gives an ended job and a retired row the same fields. The worktree tier
# comes from the rows of both lists: the script reads the marker once for
# each distinct cwd. One session gives one line, also when its session file
# and its marker both name the folder.
#
# The --all list keeps the rows of ended background jobs only: an
# interactive session leaves the list when it ends (checked on 2026-11-01).
# So the worktree tier finds a running interactive session, but not an
# ended one.
#
# A file joins to a job row by its job_session_id field, by the sessionId of
# a row, or by the job id of a row: the 8-character `id`, which is the first 8
# characters of the first session id of the job. A /clear gives a background
# session a new session id and keeps its job id, so the files of one job,
# before and after a /clear, give one line. An interactive session has no
# job id, so it joins by its sessionId only.
#
# Output (stdout): one line for each session, newest first. The time of a
# session is the newest written_at of its session files, or the startedAt of
# its row for a session that holds the folder through its marker:
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
#               ended    no live row, and the transcript below exists
#               gone     no process, and the transcript below does not
#                        exist: Claude Code deleted it (cleanupPeriodDays).
#                        This is an ended job, or a retired row, which can
#                        stay in the list for longer than the cleanup
#                        period. A resume or an attach gives an empty
#                        conversation with no history and no name, so no
#                        caller restarts it or attaches to it.
#               moved    the job moved to another folder: the file of its
#                        live session id, else its newest session file by
#                        written_at, names another folder. The older file
#                        that names this folder does not hold it, so no
#                        caller counts the row as a holder, and no caller
#                        restarts it for this folder. The reader in
#                        session-file.sh gives the job the other folder.
#                        A session with no job cannot move.
#
# The transcript of a session with no process (ended or retired) is the one
# of the conversation that `claude --bg --resume` or `claude attach` loads:
# <projects dir>/*/<conversation id>.jsonl. The conversation id is the
# resumeSessionId of the job record, <jobs dir>/<job id>/state.json, when the
# record exists and the field is one plain token: a /clear gives the job a
# new conversation, and the cleanup can delete the transcript of the first
# id first. Else it is the session id field. The projects dir is
# FOLDER_SESSIONS_PROJECTS_DIR, default ${CLAUDE_CONFIG_DIR:-~/.claude}/projects,
# and the jobs dir is FOLDER_SESSIONS_JOBS_DIR, default
# ${CLAUDE_CONFIG_DIR:-~/.claude}/jobs. A running session gets no check,
# because no caller restarts it, and a moved session gets none, because no
# caller restarts it for this folder.
#
# No output means that no session claims the folder. The script reads both
# lists also then, because only the rows show a session that holds the folder
# through its marker.
#
# Exit codes:
#   0  — the list is complete, possibly empty
#   1  — usage error (H001) or a folder that is not an existing absolute
#        directory (H002)
#   2  — the sessions cannot be read: jq is missing (H003),
#        `claude agents --json` failed (H004), or a session is ended or
#        retired and the projects dir does not exist (H005), so ended or
#        retired and gone cannot be told apart. stdout is empty. A caller
#        decides what a failed check means for it.

set -euo pipefail

readonly ERR_USAGE="H001"
readonly ERR_FOLDER="H002"
readonly ERR_NO_JQ="H003"
readonly ERR_AGENTS="H004"
readonly ERR_PROJECTS="H005"

readonly PROJECTS_DIR="${FOLDER_SESSIONS_PROJECTS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects}"
readonly JOBS_DIR="${FOLDER_SESSIONS_JOBS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jobs}"

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
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/marker-file.sh"

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

# No sessions directory means that no session file claims any folder. A
# session can still hold the folder through its marker.
files="$(_issue_context_sessions_of_folder "$folder")" || files=""
owners="$(_issue_context_session_owners)" || owners=""

self_id=""
self_first=""
if [ "$others" -eq 1 ]; then
  self_id="${CLAUDE_CODE_SESSION_ID:-}"
  _issue_context_job_first_id self_first || self_first=""
  # The files of the caller go first. The jq join below also leaves out a
  # caller that only a row names, such as a caller that holds the folder
  # through its marker.
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

# marker_names_folder <cwd> — 0 when the marker of the worktree of <cwd> is
# a path that resolves to the folder. A subshell, so the cd stays in it. A
# cwd that no longer exists, a cwd outside git, and a mode marker give 1.
marker_names_folder() {
  (
    cd "$1" 2>/dev/null || exit 1
    m_folder=""
    # shellcheck disable=SC2034 # m_reason is set through its name; any reason means no folder
    m_reason=""
    _issue_context_marker_read m_folder m_reason || exit 1
    m_phys="$({ cd "$m_folder" && pwd -P; } 2>/dev/null)" || exit 1
    [ "$m_phys" = "$folder" ]
  )
}

# The cwd values whose marker names the folder, one JSON string each. Each
# distinct cwd is read once, because many rows share one worktree.
marker_cwds="[]"
while IFS= read -r m_cwd; do
  [ -n "$m_cwd" ] || continue
  if marker_names_folder "$m_cwd"; then
    marker_cwds="$(printf '%s' "$marker_cwds" | jq -c --arg c "$m_cwd" '. + [$c]')"
  fi
done <<CWDS
$(jq -n -r --argjson live "$live" --argjson all "$all" \
  '[($live[], $all[]) | .cwd | strings | select(startswith("/") and (test("[\n\r]") | not))] | unique[]')
CWDS

# The state rule needs a file test for the transcript, which jq cannot make,
# so the jq program gives ended, and the loop after it gives gone. The list
# is held first, so an H005 exit leaves stdout empty.
listing="$(printf '%s\n' "$files" | jq -R -n -r '
  # kcov-exclude-start
  def clean: tostring | gsub("[\t\n\r]"; " ");
  def jobid: if type == "string" and length >= 8 then .[0:8] else null end;
  def epoch: try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch 0;
  def token: type == "string" and test("^[A-Za-z0-9_-]+$");
  # The session ids and the job ids of all session files, whatever folder
  # they name: a session in this set never holds through its marker.
  ($owners | split("\n") | map(select(. != "") | split("\t")
     | {sid: .[0], job: (((.[1] // "") | jobid) // (.[0] | jobid)),
        written: (.[2] // ""), folder: (.[3] // "")})) as $own
  | [inputs | split("\t") | select(length >= 2 and .[1] != "")
   | {written: .[0], sid: .[1], first: (if (.[2] // "") == "" then null else .[2] end)}]
  # The job of each file: its job_session_id first, then the row with its
  # sessionId (live before ended), then the job row whose id it starts with.
  | map(. as $f
      | (if $f.first then ($f.first | jobid)
         else (first(($live[], $all[]) | select(.sessionId == $f.sid) | .id) //
               first(($live[], $all[]) | select(.id != null and .id == ($f.sid | jobid)) | .id) //
               # A file of a later session of the job names this id as its
               # first id, so this id began a job.
               (if any($own[]; .sid != $f.sid and .job == ($f.sid | jobid))
                then ($f.sid | jobid) else null end) //
               null)
         end) as $job
      | . + {job: $job, key: (if $job then "job:" + $job else "sid:" + $f.sid end)})
  # One group for each job, in the order of its newest file.
  | reduce .[] as $f ({order: [], groups: {}};
      if .groups[$f.key] then .groups[$f.key] += [$f]
      else .order += [$f.key] | .groups[$f.key] = [$f] end)
  | .groups as $g
  | [.order[] | $g[.] as $files
     | {job: $files[0].job, sids: [$files[].sid],
        firsts: [$files[].first | select(. != null)],
        t: ([$files[].written | epoch] | max // 0)}] as $by_file
  # The worktree tier: a row whose cwd has a marker that names the folder,
  # and whose session and job have no session file.
  | [($live[], $all[])
     | select((.cwd as $c | $mcwds | index($c)) != null and (.sessionId | token))
     | (.id | jobid) as $job
     | .sessionId as $sid
     | select(([$own[] | select(.sid == $sid or ($job != null and .job == $job))]
               | length) == 0)
     | {key: (if $job then "job:" + $job else "sid:" + $sid end),
        job: $job, sids: [$sid], firsts: [], t: ((.startedAt // 0) / 1000)}]
    | unique_by(.key) | map(del(.key)) as $by_marker
  | ($by_file + $by_marker) | sort_by(- .t) | .[]
  | .job as $job
  | .sids as $sids
  | .firsts as $firsts
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
       (first($firsts[]) //
        first($arow.sessionId | select(. != null and jobid == $job)) //
        first($sids[] | select(jobid == $job)) //
        $sids[0])
     else $sids[0] end) as $session
  # A move: the folder of a job is the one of the file of its live session
  # id, else the one of its newest file, the rule of the reader in
  # session-file.sh. When that folder is another one, the job does not hold
  # this folder. A session with no job has one id, so it cannot move.
  | (if $job == null then null
     else [$own[] | select(.job == $job)] as $jf
       | ((if ($lrow.sessionId // null | token) then
             [$jf[] | select(.sid == $lrow.sessionId)] | sort_by(.written | epoch) | last
           else null end)
          // ($jf | sort_by([(.written | epoch), .sid]) | last)
          // null)
       | if . == null then null else .folder end
     end) as $job_folder
  | (if $job_folder != null and $job_folder != "" and $job_folder != $folder
     then "moved" else $state end) as $state
  | [$session, ($job // "-"),
     (($lrow.name // $arow.name // "") | clean | if . == "" then "-" else . end), $state]
  | join("\t")
  # kcov-exclude-end
' --argjson live "$live" --argjson all "$all" --argjson mcwds "$marker_cwds" --arg owners "$owners" --arg self_id "$self_id" --arg self_job "${self_first:0:8}" --arg folder "$folder")"

# has_transcript <session id> <job id> — 0 when the transcript of the
# conversation that a resume loads exists. See the header.
has_transcript() {
  local conv="" candidate
  if [ "$2" != "-" ] && [ -r "$JOBS_DIR/$2/state.json" ]; then
    conv="$(jq -r '.resumeSessionId | strings' "$JOBS_DIR/$2/state.json" 2>/dev/null || true)"
  fi
  [[ "$conv" =~ ^[A-Za-z0-9_-]+$ ]] || conv="$1"
  for candidate in "$PROJECTS_DIR"/*/"$conv.jsonl"; do
    [ -f "$candidate" ] && return 0
  done
  return 1
}

case "$listing" in
  *$'\t'ended | *$'\t'ended$'\n'* | *$'\t'retired | *$'\t'retired$'\n'*)
    [ -d "$PROJECTS_DIR" ] \
      || die 2 "$ERR_PROJECTS" "the transcript directory $PROJECTS_DIR does not exist, so it is unknown whether the sessions of $folder that do not run still have their history"
    ;;
esac

while IFS=$'\t' read -r l_sid l_job l_name l_state; do
  [ -n "$l_sid" ] || continue
  case "$l_state" in
    ended | retired)
      has_transcript "$l_sid" "$l_job" || l_state="gone"
      ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$l_sid" "$l_job" "$l_name" "$l_state"
done <<LISTING
$listing
LISTING
