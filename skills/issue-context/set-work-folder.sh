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
#   set-work-folder.sh <folder> [name]   set the override for this session
#   set-work-folder.sh --clear           remove this session's override
#   set-work-folder.sh --help
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

  <folder>  Absolute path to an existing directory
  [name]    Optional readable label for the session file's name
  --clear   Remove this session's override
  --help    Show this help message
EOF
}

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/session-file.sh"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/slugify.sh"

die() {
  echo "set-work-folder $1 error: $2" >&2
  exit 1
}

# --- Parse arguments ---
clear_mode=0
folder=""
name=""

case "${1-}" in
  --help)
    usage
    exit 0
    ;;
  --clear)
    [ "$#" -eq 1 ] || die "$ERR_USAGE" "--clear takes no other arguments"
    clear_mode=1
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

# --- The session is the identity, so it is required for both modes ---
# CLAUDE_CODE_SESSION_ID survives a session moving to a background spare; the
# process behind the session does not, which is why nothing here keys off a
# process id or an exported variable.
[ -n "${CLAUDE_CODE_SESSION_ID:-}" ] \
  || die "$ERR_NO_SESSION" "CLAUDE_CODE_SESSION_ID is not set, so there is no session to set a folder for"

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
# reach this line at once.
mv -f "$tmp" "$target" || die "$ERR_WRITE" "could not write $target"
trap - EXIT

# One writer rule, enforced after the write: $target is kept because it is the
# file just installed, and every older name this session owns goes. Failing
# here is fatal even though the override was written, because what survives is
# the duplicate the reader refuses.
remove_existing "$target" >/dev/null \
  || die "$ERR_WRITE" "wrote $target but could not remove an older session file beside it; both remain, and the override is refused as a duplicate until one is deleted"

echo "set-work-folder: working files for this session now go to $folder_phys" >&2
printf '%s\n' "$target"
