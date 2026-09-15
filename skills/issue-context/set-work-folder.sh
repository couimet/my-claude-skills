#!/usr/bin/env bash
#
# set-work-folder.sh — Point this session's working files at a folder.
#
# Every working file a session writes (notes, questions, scratchpads, commit
# messages) is placed by get-issue-folder-path.sh, which resolves the current
# session's override before falling back to branch-derived placement. This
# script writes that override. A repository organised by topic can therefore
# say where its files belong, instead of having the branch decide.
#
# Usage:
#   set-work-folder.sh <folder> [name]        set the override for this session
#   set-work-folder.sh --clear                remove this session's override
#   set-work-folder.sh --worktree <folder>    set this worktree's marker
#   set-work-folder.sh --clear --worktree     remove this worktree's marker
#   set-work-folder.sh --help
#
# The session modes write a document keyed on CLAUDE_CODE_SESSION_ID that dies
# with the session. The worktree modes write CLAUDE_WORK_FOLDER at the worktree
# root, which lives until someone deletes it and needs no session at all. Both
# refuse a relative path and a directory that does not exist, so a typo is read
# here, where someone is watching, rather than days later by a resolver that
# falls back in silence.
#
#   <folder>  Absolute path to an existing directory. It is not required to be
#             inside any repository: a session is not pinned to one, and the
#             resolver refuses an override that does not belong to the
#             repository it is resolving in.
#   [name]    Optional readable label for the filename. Absent, the name is
#             read from $CLAUDE_JOB_DIR/state.json; absent there too, the
#             filename carries no label. Nothing is ever looked up by label.
#
# The override is SESSION-WIDE. Subagents launched through the Agent tool run
# in the same process and inherit CLAUDE_CODE_SESSION_ID, so a subagent that
# calls this changes the folder for its parent and its siblings too.
#
# Output: setting a folder prints the path of the file written, one line on
# stdout. --clear prints nothing on stdout: it may remove one file or none, and
# naming the sessions directory instead would read as though that were what it
# removed. Both modes say what happened on stderr.
#
# Exit codes:
#   0  — success
#   1  — error (see stderr)

set -euo pipefail

readonly ERR_USAGE="S001"
readonly ERR_NO_SESSION="S002"
readonly ERR_FOLDER="S003"
readonly ERR_NO_JQ="S004"
readonly ERR_WRITE="S005"

usage() {
  cat <<'EOF'
Usage: set-work-folder.sh <folder> [name]
       set-work-folder.sh --clear
       set-work-folder.sh --worktree <folder>
       set-work-folder.sh --clear --worktree

  <folder>     Absolute path to an existing directory
  [name]       Optional readable label for the session file's name
  --clear      Remove this session's override
  --worktree   Write or clear this worktree's CLAUDE_WORK_FOLDER marker
               instead of this session's override
  --help       Show this help message
EOF
}

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/session-file.sh"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/slugify.sh"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/marker-file.sh"

die() {
  echo "set-work-folder $1 error: $2" >&2
  exit 1
}

# --- Parse arguments ---
clear_mode=0
worktree_mode=0
folder=""
name=""

case "${1-}" in
  --help)
    usage
    exit 0
    ;;
  --clear)
    case "${2-}" in
      "") [ "$#" -eq 1 ] || die "$ERR_USAGE" "--clear takes no other arguments" ;;
      --worktree)
        [ "$#" -eq 2 ] || die "$ERR_USAGE" "--clear --worktree takes no other arguments"
        worktree_mode=1
        ;;
      *) die "$ERR_USAGE" "--clear takes no other arguments" ;;
    esac
    clear_mode=1
    ;;
  --worktree)
    [ "$#" -eq 2 ] || die "$ERR_USAGE" "--worktree takes exactly one folder"
    worktree_mode=1
    folder="$2"
    ;;
  "")
    usage >&2
    die "$ERR_USAGE" "a folder is required"
    ;;
  -*)
    die "$ERR_USAGE" "unknown flag '$1'"
    ;;
  *)
    [ "$#" -le 2 ] || die "$ERR_USAGE" "expected 1-2 arguments, got $#"
    folder="$1"
    name="${2-}"
    ;;
esac

# --- Worktree modes: the worktree is the identity, so no session is needed ---
# A marker belongs to a checkout, not to a conversation, which is the whole
# reason it outlives one. Requiring a session id here would refuse the mode in
# exactly the place it is most useful: a shell with no Claude session at all.
if [ "$worktree_mode" -eq 1 ]; then
  marker="$(_issue_context_marker_path)" \
    || die "$ERR_FOLDER" "not inside a git repository, so there is no worktree root to write $_ISSUE_CONTEXT_MARKER_NAME at"

  if [ "$clear_mode" -eq 1 ]; then
    if [ -e "$marker" ]; then
      rm -f "$marker" \
        || die "$ERR_WRITE" "could not remove $marker, so the worktree marker is still in effect"
      echo "set-work-folder: cleared this worktree's folder marker" >&2
    else
      # Not an error, for the same reason --clear is not: the caller asked for
      # a state that is already the state.
      echo "set-work-folder: no folder marker was set for this worktree" >&2
    fi
    exit 0
  fi

  case "$folder" in
    /*) ;;
    *) die "$ERR_FOLDER" "'$folder' is not an absolute path" ;;
  esac
  [ -d "$folder" ] \
    || die "$ERR_FOLDER" "'$folder' is not an existing directory (create it first, or fix the path)"
  folder_phys="$(cd "$folder" && pwd -P)" \
    || die "$ERR_FOLDER" "'$folder' could not be resolved"

  # Written canonicalised, so the file says where the folder actually is rather
  # than how it was typed. A hand-authored ~/ still expands on read.
  printf '%s\n' "$folder_phys" > "$marker" \
    || die "$ERR_WRITE" "could not write $marker"

  echo "set-work-folder: working files for this worktree now go to $folder_phys" >&2
  printf '%s\n' "$marker"
  exit 0
fi

# --- The session is the identity, so it is required for both session modes ---
# CLAUDE_CODE_SESSION_ID survives a session moving to a background spare; the
# process behind the session does not, which is why nothing here keys off a
# process id or an exported variable.
[ -n "${CLAUDE_CODE_SESSION_ID:-}" ] \
  || die "$ERR_NO_SESSION" "CLAUDE_CODE_SESSION_ID is not set, so there is no session to set a folder for"

# Refused here, before sessions_dir is resolved, so neither mode can reach a
# path built from an id that is not a filename component. `../settings` names
# the settings file the sessions directory sits beside: the write would
# overwrite it and --clear would delete it.
_issue_context_session_id_ok \
  || die "$ERR_NO_SESSION" "CLAUDE_CODE_SESSION_ID '$CLAUDE_CODE_SESSION_ID' cannot be a filename component, so no session file can be named for it"

sessions_dir="$(_issue_context_sessions_dir)" \
  || die "$ERR_NO_SESSION" "could not resolve the sessions directory from the settings path"

# --- Remove every file this session already owns ---
# One writer rule: a session keeps exactly one file. Without it, a call with no
# name followed by a call with one would leave two files describing one
# session, and the resolver refuses a duplicate match rather than guessing.
#
# remove_existing [keep] — remove every file this session owns except [keep],
# and print how many went. Returns 1 the moment a removal fails, rather than
# letting the count fall through to a printf that always succeeds: a caller
# that mistook a failed removal for a clean one would report success over a
# file that is still routing this session's working files.
remove_existing() {
  local keep="${1-}"
  local -a existing=()
  local f removed=0
  if _issue_context_session_file_matches existing; then
    # ${arr[@]+"${arr[@]}"} rather than "${arr[@]}": bash before 4.4 treats an
    # empty array as unset, and set -u then aborts the script on the ordinary
    # case of a session that has no file yet. macOS ships bash 3.2.
    for f in ${existing[@]+"${existing[@]}"}; do
      # The keep path is compared as a string, which holds because it and the
      # glob that produced $f are both built on _issue_context_sessions_dir.
      [ "$f" != "$keep" ] || continue
      rm -f "$f" || return 1
      removed=$((removed + 1))
    done
  fi
  printf '%s' "$removed"
}

if [ "$clear_mode" -eq 1 ]; then
  removed="$(remove_existing)" \
    || die "$ERR_WRITE" "could not remove this session's file, so the folder override is still in effect"
  if [ "${removed:-0}" -gt 0 ]; then
    echo "set-work-folder: cleared this session's folder override" >&2
  else
    # Not an error. Clearing something already absent is the state the caller
    # asked for, and repeating the command must not start failing.
    echo "set-work-folder: no folder override was set for this session" >&2
  fi
  exit 0
fi

# --- Validate the folder ---
case "$folder" in
  /*) ;;
  *) die "$ERR_FOLDER" "'$folder' is not an absolute path" ;;
esac

# Refusing a missing folder, rather than warning or creating it. A typo is read
# immediately here, where someone is watching; the resolver's matching silence
# is right because nothing is watching it days later. Creating the folder would
# turn a typo into a junk directory that resolves forever.
[ -d "$folder" ] \
  || die "$ERR_FOLDER" "'$folder' is not an existing directory (create it first, or fix the path)"

folder_phys="$(cd "$folder" && pwd -P)" \
  || die "$ERR_FOLDER" "'$folder' could not be resolved"

# --- Derive the slug ---
# Order matters: an explicit name, then the job state file, then nothing. This
# keeps the script usable with no arguments while keeping the dependency on an
# undocumented internal file optional. If Claude Code renames that key, the
# sessions directory loses some readability and keeps working.
slug=""
if [ -n "$name" ]; then
  slug="$(_issue_context_slugify "$name" "$_ISSUE_CONTEXT_SESSION_SLUG_MAX")"
elif [ -n "${CLAUDE_JOB_DIR:-}" ] && [ -r "$CLAUDE_JOB_DIR/state.json" ] \
    && command -v jq >/dev/null 2>&1; then
  job_name="$(jq -r 'if (.name | type == "string") then .name else empty end' \
    "$CLAUDE_JOB_DIR/state.json" 2>/dev/null || true)"
  if [ -n "${job_name:-}" ]; then
    slug="$(_issue_context_slugify "$job_name" "$_ISSUE_CONTEXT_SESSION_SLUG_MAX")"
  fi
fi

# _issue_context_slugify never returns empty, so an explicit name of "!!!"
# becomes "file". That is a readable-half artifact and routing ignores it.
if [ -n "$slug" ]; then
  target="$sessions_dir/${CLAUDE_CODE_SESSION_ID}--${slug}.json"
else
  target="$sessions_dir/${CLAUDE_CODE_SESSION_ID}.json"
fi

# --- Write ---
command -v jq >/dev/null 2>&1 \
  || die "$ERR_NO_JQ" "jq not found; it is required to write a correctly escaped session file"

mkdir -p "$sessions_dir" || die "$ERR_WRITE" "could not create $sessions_dir"

# Local time is fine for a human-facing "when was this set", but this field is
# read by people comparing sessions, so UTC keeps it unambiguous.
written_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# written_by is best-effort, not an identity. Claude Code exposes no stable
# identifier for a subagent, so these three values are what is available to
# trace a surprising change after the fact. CLAUDE_CODE_CHILD_SESSION reads 1
# in a top-level session too, so it records what the variable said rather than
# proving a subagent wrote this.
tmp="$(mktemp "$sessions_dir/.tmp-XXXXXX")" \
  || die "$ERR_WRITE" "could not create a temporary file in $sessions_dir"
trap 'rm -f "$tmp"' EXIT

jq -n \
  --argjson version "$_ISSUE_CONTEXT_SESSION_VERSION" \
  --arg folder "$folder_phys" \
  --arg session_id "$CLAUDE_CODE_SESSION_ID" \
  --arg slug "$slug" \
  --arg written_at "$written_at" \
  --arg agent "${CLAUDE_CODE_AGENT:-}" \
  --arg pid "${CLAUDE_PID:-}" \
  --arg child "${CLAUDE_CODE_CHILD_SESSION:-}" \
  '{
     version: $version,
     folder: $folder,
     session_id: $session_id,
     slug: (if $slug == "" then null else $slug end),
     written_at: $written_at,
     written_by: {
       agent: (if $agent == "" then null else $agent end),
       pid: (if $pid == "" then null else ($pid | tonumber? // $pid) end),
       child_session: (if $child == "" then null else ($child != "0") end)
     }
   }' > "$tmp" || die "$ERR_WRITE" "could not compose the session file"

# The rename comes first and the cleanup after. mv within one directory is
# atomic, so a resolver reading at the same instant sees either no file or the
# complete one, never a half-written document, and a rewrite that lands on the
# same name replaces the old document in a single step with no gap at all.
# Removing first would open the opposite gap, a moment with no file, and the
# resolver says nothing when it finds nothing: a working file would land in
# the branch-derived folder with no sign that anything was wrong. Only a
# changed slug still leaves two files for an instant, and the resolver reports
# that as a duplicate rather than falling back in silence.
# Subagents share their parent's session id, so two agents in one session can
# reach this line at once, which is what the surviving-file check below is for.
mv -f "$tmp" "$target" || die "$ERR_WRITE" "could not write $target"
trap - EXIT

# One writer rule, enforced after the write: $target is kept because it is the
# file just installed, and every older name this session owns goes. Failing
# here is fatal even though the override was written, because what survives is
# the duplicate the reader refuses.
remove_existing "$target" >/dev/null \
  || die "$ERR_WRITE" "wrote $target but could not remove an older session file beside it; both remain, and the override is refused as a duplicate until one is deleted"

# Nothing above serializes two writers. Two agents in one session passing
# different names install two files and then remove each other's in their own
# cleanup, and without this both would report success over a session that has
# no file left. The loser says so instead. Serializing them properly wants a
# lock this script does not have (macOS ships no flock), and the point of
# failing here is that a race nobody has hit yet leaves evidence if it is.
[ -f "$target" ] \
  || die "$ERR_WRITE" "$target did not survive its own cleanup, which is what happens when another agent in this session wrote a different name at the same moment; the folder is not set"

echo "set-work-folder: working files for this session now go to $folder_phys" >&2
printf '%s\n' "$target"
