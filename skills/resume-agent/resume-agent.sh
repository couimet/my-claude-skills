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
# The session of a folder, and its state, come from
# ../issue-context/folder-sessions.sh --others, the one rule that every
# caller uses, with the transcript and job record directories of this
# script. It joins the session files that set-work-folder.sh writes to
# `claude agents --json` by session id and by job id, so a session after a
# /clear is still found. The session that runs this script is left out, so a
# person who types the skill in the folder's own session does not restart it.
# When more sessions remain, the newest session file wins, and stderr names
# the others. An older session whose job record continues in the conversation
# of the newer one (its resumeSessionId, in RESUME_AGENT_JOBS_DIR/<job
# id>/state.json, default ${CLAUDE_CONFIG_DIR:-~/.claude}/jobs) is named as
# the earlier part of the same work.
#
# The state decides the action:
#
#   running  the job has a process or a status. Nothing restarts it, because
#            `claude --bg --resume` on a running session starts a copy.
#   retired  the job is listed with no process and no status. On Claude Code
#            2.1.302, `claude --bg --resume` of it starts a copy, and
#            `claude attach <job id>` wakes it with one job record, but that
#            command needs a terminal. So nothing restarts it, Status is
#            retired, and stderr gives the attach command.
#   gone     the job is not listed, and Claude Code deleted the transcript
#            of the conversation that a resume loads. A resume gives an
#            empty conversation with no history, which Claude Code names
#            from its first prompt. So nothing restarts, stdout is empty, and
#            the script stops with R008. It does not try an older session of
#            the folder: an older session misses the later rounds, and a
#            resume of it looks like a success. The R008 message gives
#            /launch-agent <folder>, and when the cwd of the job row (source 1
#            below) is not the git top-level of the folder, the directory to
#            run it in. A failed read of that row gives R008 with the short
#            advice, never R004.
#   ended    the job is not listed. `claude --bg --resume <session id>` wakes
#            it with no prompt, idle, under the name it was saved with. For a
#            job, the session id is the first session id of the job: a resume
#            of it keeps one job record and continues the newest
#            conversation, where a resume of a later conversation id makes a
#            second record. No flag is passed: with a flag such as --name,
#            Claude Code 2.1.296 starts a copy under a new id instead of the
#            session. The script then reads the list again and checks that
#            the session is there.
#
# A session reads the project .claude/settings.json and CLAUDE.md from the
# directory it starts in only. On Claude Code 2.1.302, a resume of the first
# session id of a job record that exists starts in the launch directory of the
# job, whatever the directory of the command. A resume that makes a new job
# record, such as a resume of the conversation id of a cleared session, starts
# in the directory of the command. So the restart runs in the directory that
# the session is expected in, in this order:
#
#   1. the cwd of the job row in `claude agents --json --all`, the launch
#      directory of the job. A Bash cd and a /clear do not change it.
#   2. the first cwd field of the transcript, past any line that is not JSON,
#      RESUME_AGENT_PROJECTS_DIR/*/<session id>.jsonl (default
#      ${CLAUDE_CONFIG_DIR:-~/.claude}/projects). A Bash cd moves the cwd that
#      a transcript records, so this is the second source only.
#   3. the git top-level of the folder, or the folder itself when it is in no
#      repository: the rule of launch-agent.sh.
#
# A session can start in another repository than the one of its folder, so
# the folder alone does not give this directory. stderr says when the
# directory does not come from the job row or the transcript.
#
# The script then compares the cwd that `claude agents --json` reports with
# that directory. After a restart, a different cwd is R007: a check that
# Claude Code still starts the session there. For a session that already
# runs, a different cwd is a warning on stderr, because nothing restarted. A
# missing cwd is a warning in both cases, because the session runs.
#
# Right after a restart, `claude agents` lists the session under its short id
# until the session loads its saved name. Until then, the agent view search
# and a send by name cannot find the session by its name. So the script reads
# the list again every second for up to RESUME_AGENT_NAME_WAIT seconds
# (default 15), and the Name line gives only a name that the list shows. A
# name that is still the short id after that is reported as not loaded, never
# as a different name. When the "backgrounded · <id> · <name>" line of the
# restart output has a name, stderr gives it as the name the session will
# load.
#
# Claude Code takes the name of a restarted session from its job record, and
# only a /rename typed in the session changes it, so the Rename line tells the
# user how to give it the folder name. The agent view opens a record by name,
# and another record with the same name, live or ended, makes it pick the
# wrong one. So stderr names each such record with its command (claude stop
# for a live one, claude rm for an ended one; on 2.1.302, claude rm deletes
# the job record and its worktree, and keeps the transcript), and the Open
# line is left out.
#
# The script sends no prompt and attaches nothing. A caller sends its own
# prompt, and a person opens the session from the agent view or with the
# attach command.
#
# The Address line is the cross-session address of the session's process,
# uds:<socket dir>/<pid>.sock. A short id is not a SendMessage address, and
# two live sessions can share a name, so this is the one address that always
# names exactly this session. No Claude Code doc defines the socket dir
# (RESUME_AGENT_SOCKET_DIR, default /tmp/cc-socks), so the line is printed
# only when that socket exists, and stderr says so when it does not.
#
# Output (stdout), one labelled line each, in this order:
#   Folder:   the resolved folder
#   Session:  the full session id
#   Id:       the short id, the first 8 characters of the session id
#   Name:     the name the session runs under, or "not loaded yet"
#   Status:   the status `claude agents` reports: idle (at the prompt), busy
#             (a turn runs), waiting (a permission answer), retired (no
#             process; see above), or unknown
#   State:    the state `claude agents` reports, such as blocked or done, or
#             unknown
#   Action:   restarted, already running, or not restarted (retired)
#   Pid:      the process id of the session, or none
#   Address:  uds:<socket dir>/<pid>.sock, only when that socket exists
#   Attach:   claude attach <short id>
#   Open:     how a person opens the session with no shell command, only
#             when the name is loaded and no other record has it
#   Rename:   the /rename command for the folder name, after each restart,
#             and for a session that already ran when its name is not the
#             folder name
#   Note:     do not run claude --bg --resume, because that starts a copy
#
# Exit codes:
#   0  — the session runs (it ran already, or it restarted), or it is retired
#        and stderr gives the command that wakes it
#   1  — error (see stderr): R001 usage, R002 folder, R003 no session file,
#        R004 `claude agents --json` failed and nothing restarted, R005
#        restart failed, R006 the restart ran but `claude agents --json` then
#        failed, so the state of the session is unknown, R007 the session
#        restarted in another directory than the one the script used, R008
#        Claude Code deleted the transcript of the session, so nothing
#        restarted

set -euo pipefail

readonly ERR_USAGE="R001"
readonly ERR_FOLDER="R002"
readonly ERR_NO_SESSION="R003"
readonly ERR_AGENTS="R004"
readonly ERR_RESTART="R005"
readonly ERR_UNKNOWN="R006"
readonly ERR_CWD="R007"
readonly ERR_GONE="R008"

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

[ -d "$sessions_dir" ] || die "$ERR_NO_SESSION" "no session has its working files in $folder_abs, so there is no session to resume; start one with /launch-agent"

readonly PROJECTS_DIR="${RESUME_AGENT_PROJECTS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects}"
readonly JOBS_DIR="${RESUME_AGENT_JOBS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jobs}"

# folder-sessions.sh is the one rule for the state of a session; see the
# header. It gets the directories of this script, so the state and the start
# directory come from one transcript directory. Its own stderr line says why
# it failed.
listing=""
rc=0
listing="$(FOLDER_SESSIONS_PROJECTS_DIR="$PROJECTS_DIR" FOLDER_SESSIONS_JOBS_DIR="$JOBS_DIR" \
  "$_self_dir/../issue-context/folder-sessions.sh" --others "$folder_abs")" || rc=$?
case "$rc" in
  0) ;; # kcov-exclude-line
  2) die "$ERR_AGENTS" "the sessions of $folder_abs could not be read, so their state is unknown; nothing was restarted" ;;
  *) die "$ERR_FOLDER" "the sessions of $folder_abs could not be listed" ;;
esac

session_id=""
job_id=""
list_state=""
others=()
while IFS=$'\t' read -r sid jid _name st; do
  [ -n "$sid" ] || continue
  [ "$jid" != "-" ] || jid=""
  if [ -z "$session_id" ]; then
    session_id="$sid"
    job_id="$jid"
    list_state="$st"
  else
    others+=("$sid:$jid:$st")
  fi
done <<LISTING
$listing
LISTING

[ -n "$session_id" ] \
  || die "$ERR_NO_SESSION" "no session other than this one has its working files in $folder_abs, so there is no session to resume; start one with /launch-agent"
# The id reaches a command line and a jq filter, so it must be one plain token.
[[ "$session_id" =~ ^[A-Za-z0-9_-]+$ ]] \
  || die "$ERR_NO_SESSION" "the session file for $folder_abs holds the session id '$session_id', which is not a valid id"

# continued_as <job id> — print the conversation id that the job record of
# <job id> continues in, or nothing. The record is the job state of Claude
# Code, an undocumented file, so a change of its shape gives nothing.
continued_as() {
  [ -n "$1" ] && [ -r "$JOBS_DIR/$1/state.json" ] || return 0
  jq -r '.resumeSessionId | strings' "$JOBS_DIR/$1/state.json" 2>/dev/null || true
}

# A job record that continues in the conversation of the chosen session is
# the earlier part of the same work, not a separate one.
for other in ${others[@]+"${others[@]}"}; do
  other_id="${other%%:*}"
  other_rest="${other#*:}"
  other_job="${other_rest%%:*}"
  other_gone=""
  [ "${other_rest#*:}" != "gone" ] || other_gone="; Claude Code deleted its transcript"
  if [ -n "$other_job" ] && [ "$(continued_as "$other_job")" = "$session_id" ]; then
    echo "resume-agent: another session also used this folder: $other_id continued as $session_id (not resumed; it is the earlier part of the same work$other_gone)" >&2
  else
    echo "resume-agent: another session also used this folder: $other_id (not resumed; the newest one wins$other_gone)" >&2
  fi
done

# --- Choose the directory of the session ---
# See the header for why it is the launch directory of the job, and not the
# directory of the caller.
all_list=""
if ! all_list="$(claude agents --json --all 2>/dev/null)" \
    || ! printf '%s' "$all_list" | jq -e 'type == "array"' >/dev/null 2>&1; then
  # For a gone session the row only improves the advice, so R008 stands.
  [ "$list_state" = "gone" ] \
    || die "$ERR_AGENTS" "claude agents --json --all failed, so the state of session $session_id is unknown; nothing was restarted"
  all_list="[]"
fi
# ROW is the jq condition that picks the row of the session: its job id, or
# its session id for a session with no job.
# shellcheck disable=SC2016 # a jq program: $job and $id are jq variables
readonly ROW='if $job != "" then .id == $job else .sessionId == $id end'
job_cwd="$(printf '%s' "$all_list" | jq -r --arg id "$session_id" --arg job "$job_id" "first(.[] | select($ROW) | .cwd | strings) // empty")"

# --- Stop on a gone session ---
# See the header: no restart, and no older session in its place.
if [ "$list_state" = "gone" ]; then
  gone_conv="$(continued_as "$job_id")"
  [[ "$gone_conv" =~ ^[A-Za-z0-9_-]+$ ]] || gone_conv="$session_id"
  advice="start a new session for the folder with /launch-agent $folder_abs"
  gone_dir=""
  case "$job_cwd" in
    /*) gone_dir="$({ cd "$job_cwd" && pwd -P; } 2>/dev/null || true)" ;;
  esac
  if [ -n "$gone_dir" ]; then
    gone_top="$(git -C "$folder_abs" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -z "$gone_top" ] || gone_top="$({ cd "$gone_top" && pwd -P; } 2>/dev/null || true)"
    [ "$gone_dir" = "$gone_top" ] \
      || advice="start a session in $gone_dir, and run /launch-agent $folder_abs in it"
  fi
  die "$ERR_GONE" "Claude Code deleted the transcript of session $session_id (no $gone_conv.jsonl in $PROJECTS_DIR), so a resume gives an empty conversation with no history and no name; the script restarted nothing; $advice"
fi

resume_dir=""
case "$job_cwd" in
  /*) resume_dir="$({ cd "$job_cwd" && pwd -P; } 2>/dev/null || true)" ;;
esac
if [ -n "$job_cwd" ] && [ -z "$resume_dir" ]; then
  echo "resume-agent: the job record of session $session_id gives the directory $job_cwd, which does not exist; the script reads the transcript instead" >&2
fi
transcript=""
start_cwd=""
if [ -z "$resume_dir" ]; then
  for candidate in "$PROJECTS_DIR"/*/"$session_id.jsonl"; do
    [ -f "$candidate" ] && { transcript="$candidate"; break; }
  done
  if [ -n "$transcript" ]; then
    # first() stops at the first match, so a long transcript is not read to
    # its end. -R with fromjson? skips a line that is not JSON: without it, jq
    # stops at that line and hides each cwd after it.
    start_cwd="$(jq -R -n -r 'first(inputs | fromjson? | objects | .cwd | strings)' "$transcript" 2>/dev/null || true)"
  fi
  case "$start_cwd" in
    /*) resume_dir="$({ cd "$start_cwd" && pwd -P; } 2>/dev/null || true)" ;;
  esac
fi
if [ -z "$resume_dir" ]; then
  resume_dir="$(git -C "$folder_abs" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$resume_dir" ] || resume_dir="$folder_abs"
  resume_dir="$({ cd "$resume_dir" && pwd -P; } 2>/dev/null)" || resume_dir="$folder_abs"
  if [ -z "$transcript" ]; then
    echo "resume-agent: no transcript of session $session_id in $PROJECTS_DIR, so its start directory is unknown; the script uses $resume_dir" >&2
  else
    echo "resume-agent: the transcript $transcript gives no existing start directory${start_cwd:+ ($start_cwd)}; the script uses $resume_dir" >&2
  fi
fi

# --- Read the live sessions ---
readonly NAME_WAIT="${RESUME_AGENT_NAME_WAIT:-15}"
readonly SOCKET_DIR="${RESUME_AGENT_SOCKET_DIR:-/tmp/cc-socks}"

# read_list — set `agents_list` to the `claude agents --json` array. Returns 1
# when the command fails or prints no JSON array.
agents_list=""
read_list() {
  agents_list="$(claude agents --json 2>/dev/null)" || return 1
  printf '%s' "$agents_list" | jq -e 'type == "array"' >/dev/null 2>&1
}

# entry_of — print the list entry of the session as one JSON line, or nothing
# when it is not listed.
entry_of() {
  printf '%s' "$agents_list" | jq -c --arg id "$session_id" --arg job "$job_id" \
    "[.[] | select($ROW)] | first // empty"
}

# field <name> — print one field of `entry`, or nothing when it is null.
field() {
  printf '%s' "$entry" | jq -r --arg k "$1" '.[$k] // empty'
}

short_id="${job_id:-${session_id:0:8}}"
# loaded <name> — 0 when <name> is a real name, not empty and not the short id.
loaded() {
  [ -n "$1" ] && [ "$1" != "$short_id" ]
}

read_list \
  || die "$ERR_AGENTS" "claude agents --json failed, so the state of session $session_id is unknown; nothing was restarted"
entry="$(entry_of)"

restart_name=""
retired=0
if [ "$list_state" = "running" ]; then
  action="already running"
elif [ "$list_state" = "retired" ]; then
  # See the header: a resume of a retired row starts a copy, and the command
  # that wakes it needs a terminal.
  action="not restarted"
  retired=1
  echo "resume-agent: session $session_id is retired: its job is listed with no process, and claude --bg --resume of it starts a copy, so the script restarts nothing; wake it with claude attach $short_id" >&2
else
  # No prompt, and no flag. See the header for why --name is not passed.
  restart_output="$({ cd "$resume_dir" && claude --bg --resume "$session_id"; } 2>&1)" || {
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
  restart_name="$(printf '%s\n' "$restart_output" \
    | sed -n 's/^backgrounded · [^ ]* · \(.*\)$/\1/p' | head -n 1)"
  restart_name="${restart_name% (*}"
  loaded "$restart_name" || restart_name=""

  waited=0
  while :; do
    read_list \
      || die "$ERR_UNKNOWN" "claude --bg --resume $session_id ran, but claude agents --json then failed, so it is not known whether the session runs; do not run claude --bg --resume, because a resume of a running session starts a copy; run this skill again, which restarts nothing when the session is listed"
    entry="$(entry_of)"
    if [ -n "$entry" ] && loaded "$(field name)"; then
      break
    fi
    [ "$waited" -lt "$NAME_WAIT" ] || break
    sleep 1
    waited=$((waited + 1))
  done
  [ -n "$entry" ] \
    || die "$ERR_RESTART" "claude --bg --resume $session_id returned, but claude agents does not list the session"
  action="restarted"
fi
[ -n "$entry" ] || entry="$(entry_of)"

# --- Check the directory of the session ---
listed_cwd="$(field cwd)"
if [ "$retired" -eq 1 ]; then
  : # nothing runs, so there is no directory to check
elif [ -z "$listed_cwd" ]; then
  echo "resume-agent: claude agents gives no cwd for session $session_id, so the script could not check that it runs in $resume_dir" >&2
else
  listed_cwd_abs="$({ cd "$listed_cwd" && pwd -P; } 2>/dev/null)" || listed_cwd_abs="$listed_cwd"
  if [ "$listed_cwd_abs" != "$resume_dir" ]; then
    [ "$action" != "restarted" ] \
      || die "$ERR_CWD" "session $session_id restarted in $listed_cwd, not in $resume_dir, so the project settings and CLAUDE.md of $resume_dir do not apply to it; the session runs: do not run claude --bg --resume, because that starts a copy; attach to it with claude attach $short_id and type /cd $resume_dir, or stop it with claude stop $short_id"
    echo "resume-agent: session $session_id runs in $listed_cwd, not in $resume_dir, so the project settings and CLAUDE.md of $resume_dir do not apply to it; attach to it and type /cd $resume_dir" >&2
  fi
fi

listed_id="$(field id)"
[ -z "$listed_id" ] || short_id="$listed_id"
listed_session="$(field sessionId)"
[ -z "$listed_session" ] || session_id="$listed_session"
name="$(field name)"
if ! loaded "$name" && [ -n "$restart_name" ]; then
  echo "resume-agent: the restart named the session '$restart_name', but claude agents did not show that name within $NAME_WAIT seconds; run the skill again to read the name" >&2
fi
status="$(field status)"
[ "$retired" -eq 0 ] || status="retired"
state="$(field state)"
pid="$(field pid)"

# --- Other job records ---
# Read again after a restart, so the check sees what the restart left. A
# failure keeps the list read before the restart: these lines are warnings,
# and the session runs.
if [ "$action" = "restarted" ]; then
  if after="$(claude agents --json --all 2>/dev/null)" \
      && printf '%s' "$after" | jq -e 'type == "array"' >/dev/null 2>&1; then
    all_list="$after"
  fi
fi
# other_records — print one "<id><TAB><live|ended><TAB><pid>" line for each
# job record, other than the one of the session, that has the name of the
# session. A live record and an ended record both make the agent view and a
# send by name ambiguous. The usual cause is a manual `claude --bg --resume`,
# which makes a copy or a second record.
other_records() {
  printf '%s\n' "$all_list" | jq -r --arg n "$1" --arg id "$session_id" --arg job "$short_id" \
    --argjson live "$agents_list" \
    '.[] | select(.name == $n and .id != $job and .sessionId != $id) # kcov-exclude-start
     | . as $r
     | (if any($live[]; (.id != null and .id == $r.id) or .sessionId == $r.sessionId)
        then "live" else "ended" end) as $where
     | "\(.id // .sessionId[0:8])\t\($where)\t\(.pid // "none")"' # kcov-exclude-end
}

duplicates=0
if loaded "$name"; then
  if [ "$name" != "$folder_name" ]; then
    echo "resume-agent: the session runs under the name '$name', not '$folder_name'" >&2
  fi
  while IFS=$'\t' read -r dup_id dup_where dup_pid; do
    [ -n "$dup_id" ] || continue
    duplicates=$((duplicates + 1))
    if [ "$dup_where" = "live" ]; then
      echo "resume-agent: another live session also has the name '$name': $dup_id (pid $dup_pid); if it is a copy, stop it with claude stop $dup_id" >&2
    else
      echo "resume-agent: an ended job record also has the name '$name': $dup_id; the agent view can open it in place of this session; claude rm $dup_id removes that record and its worktree, and keeps its transcript" >&2
    fi
  done <<RECORDS
$(other_records "$name")
RECORDS
else
  name=""
fi

# An ended record whose job continues in the conversation of the session is
# the record that a resume of a conversation id left behind.
if [ "$action" = "restarted" ]; then
  printf '%s\n' "$all_list" | jq -r --arg job "$short_id" --argjson live "$agents_list" \
    '.[] | select(.id != null and .id != $job) | . as $r | select(any($live[]; .id == $r.id) | not) | .id' \
    | while read -r old_id; do
        if [ -z "$old_id" ] || [ "$(continued_as "$old_id")" != "$session_id" ]; then
          continue
        fi
        echo "resume-agent: the ended job record $old_id continues in the conversation of this session, $session_id; claude rm $old_id removes that record and its worktree, and keeps its transcript" >&2
      done
fi

address=""
if [ -n "$pid" ]; then
  if [ -S "$SOCKET_DIR/$pid.sock" ]; then
    address="uds:$SOCKET_DIR/$pid.sock"
  else
    echo "resume-agent: no socket at $SOCKET_DIR/$pid.sock, so no Address line; send to the name, or ask the person" >&2
  fi
fi

printf 'Folder: %s\n' "$folder_abs"
printf 'Session: %s\n' "$session_id"
printf 'Id: %s\n' "$short_id"
printf 'Name: %s\n' "${name:-not loaded yet}"
printf 'Status: %s\n' "${status:-unknown}"
printf 'State: %s\n' "${state:-unknown}"
printf 'Action: %s\n' "$action"
printf 'Pid: %s\n' "${pid:-none}"
[ -z "$address" ] || printf 'Address: %s\n' "$address"
printf 'Attach: claude attach %s\n' "$short_id"
# The agent view picks a record by name, so Open is given only when no other
# record has the name.
if [ -n "$name" ] && [ "$duplicates" -eq 0 ]; then
  printf 'Open: in the agent view (claude agents), press Ctrl+F, type %s, and press Enter\n' "$name"
fi
# Claude Code takes the name of a restart from its job record, and only a
# /rename typed in the session changes it. So after a restart the name can be
# old, and the line is always given; for a session that already ran, only
# when its name is not the folder name.
if [ "$action" = "restarted" ] || [ "${name:-}" != "$folder_name" ]; then
  printf 'Rename: if the agent view does not show %s, open the session and type /rename %s\n' "$folder_name" "$folder_name"
fi
printf 'Note: do not run claude --bg --resume %s: the session runs, and a resume starts a copy\n' "$short_id"
