#!/usr/bin/env bash
#
# find-agent.sh — Say which session holds a work folder, or what the current
# session holds, and print the next command. It reads and never acts.
#
# Usage:
#   find-agent.sh [--others] <folder>      the verdict for a folder
#   find-agent.sh [--title <title>]        the verdict for the current session
#   find-agent.sh --check [--title <title>]
#                                          exit 0 when the current session and
#                                          its folder agree, else one line
#   find-agent.sh --help
#
#   <folder>   An absolute path, used as given, or a slug naming one directory
#              under the topic root (topic-root.sh), as /launch-agent resolves
#              it. The folder does not have to exist.
#   --others   Leave out the current session, as folder-sessions.sh --others
#              does. launch-agent.sh uses it for the advice of L007, which is
#              about another session.
#   --title    The name of the current session. The session hook passes the
#              session_title of its input, so the check reads no list. Without
#              it, the name comes from the row of the session in
#              `claude agents --json`.
#
# The holders of a folder come from folder-sessions.sh, the one rule for the
# state of a session, with the current session included and marked (unless
# --others). The
# newest holder decides, as in /resume-agent. The verdict is one value of an
# enum, so a new case adds a value and no reader changes:
#
#   launch   no holder, or the newest holder is gone (its transcript is
#            deleted): /launch-agent the folder
#   resume   the newest holder ended: /resume-agent the folder
#   attach   the newest holder is retired: claude attach <job id>
#   running  the newest holder runs under the folder name, or the current
#            session runs under the name of its folder
#   rename   the newest holder, or the current session, runs under another
#            name: /rename-agent in that session
#   moved    the current session runs under the folder name of another
#            existing folder under the topic root: /launch-agent that folder,
#            or /rename-agent to keep the bound folder
#   unbound  the current session has no session file
#
# A slug whose name is an existing folder decides moved, as /launch-agent
# resolves a slug: a name that is not one plain path segment names no folder.
#
# Output (stdout), labelled lines in this order. For a folder:
#   Verdict:  the verdict
#   Folder:   the resolved folder
#   Holder:   one line for each holder, newest first:
#             <session id> <job id or -> <state> <this|other> <name or ->
#   Next:     the exact next command, or what to do in another session
# For the current session:
#   Verdict:  the verdict
#   Session:  the session id
#   Name:     the name, or none (not for unbound)
#   Folder:   the bound folder (not for unbound)
#   Named:    the folder that the name names (moved only)
#   Next:     the first fix
#   Or:       the second choice (rename and moved only)
#
# --check prints nothing for running and unbound. For rename and moved it
# prints one line on stdout, "<verdict>: <why>; <first fix>; <second fix>",
# and exits 1. The first fix follows the verdict: /launch-agent first for
# moved, /rename-agent first for rename.
#
# The script runs no command other than `claude agents --json` (through
# folder-sessions.sh or for the name). It never starts, wakes, renames, stops,
# or removes a session: the user runs the command it prints.
#
# Exit codes:
#   0  — the verdict is printed (--check: the session and its folder agree)
#   1  — --check only: the session and its folder do not agree
#   2  — error (see stderr): G001 usage, G002 no session id, G003 folder,
#        G004 the sessions cannot be read, G005 the session file cannot be
#        read

set -euo pipefail

readonly ERR_USAGE="G001"
readonly ERR_NO_SESSION="G002"
readonly ERR_FOLDER="G003"
readonly ERR_SESSIONS="G004"
readonly ERR_SESSION_FILE="G005"

usage() {
  cat <<'EOF'
Usage: find-agent.sh [--others] <folder>
       find-agent.sh [--title <title>]
       find-agent.sh --check [--title <title>]
       find-agent.sh --help

  <folder>  Absolute path, or a slug under the topic root
  --others  Leave out the current session (with a folder only)
  --title   The name of the current session (default: from claude agents)
  --check   Exit 0 when the current session and its folder agree, else 1
            with one line
  --help    Show this help message
EOF
}

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh" 2>/dev/null
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/session-file.sh"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/topic-root.sh"

die() {
  echo "find-agent $1 error: $2" >&2
  exit 2
}

# --- Parse arguments ---
check=0
others=0
title=""
title_set=0
folder=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --check) check=1 ;;
    --others) others=1 ;;
    --title)
      [ "$#" -ge 2 ] || die "$ERR_USAGE" "--title needs a value"
      title="$2"
      title_set=1
      shift
      ;;
    -*) die "$ERR_USAGE" "unknown flag '$1'" ;;
    *)
      [ -z "$folder" ] || die "$ERR_USAGE" "expected one folder, got more"
      folder="$1"
      ;;
  esac
  shift
done
if [ -n "$folder" ] && { [ "$check" -eq 1 ] || [ "$title_set" -eq 1 ]; }; then
  die "$ERR_USAGE" "--check and --title are for the current session, not for a folder"
fi
[ -n "$folder" ] || [ "$others" -eq 0 ] \
  || die "$ERR_USAGE" "--others needs a folder"

command -v jq >/dev/null 2>&1 \
  || die "$ERR_SESSIONS" "jq not found; it is required to read the session files and the claude agents list"

self_id="${CLAUDE_CODE_SESSION_ID:-}"
self_first=""
_issue_context_job_first_id self_first || self_first=""

# folder_of_slug <name> — print the canonical folder that <name> names under
# the topic root, or nothing when it names no existing folder.
folder_of_slug() {
  # shellcheck disable=SC2034 # reason is set through its name, and not needed here
  local root="" reason=""
  case "$1" in
    '' | . | .. | */*) return 0 ;;
  esac
  _issue_context_topic_root root reason || return 0
  [ -d "$root/$1" ] || return 0
  { cd "$root/$1" && pwd -P; } 2>/dev/null || true
}

# ============================================================================
# A folder
# ============================================================================
if [ -n "$folder" ]; then
  while [ "$folder" != "/" ] && [ "${folder%/}" != "$folder" ]; do
    folder="${folder%/}"
  done
  case "$folder" in
    /*) target="$folder" ;; # kcov-exclude-line
    */* | . | ..)
      die "$ERR_FOLDER" "'$folder' is not a topic name; pass a single name, or an absolute path" ;;
    *)
      root=""
      root_reason=""
      _issue_context_topic_root root root_reason \
        || die "$ERR_FOLDER" "the topic root is unknown ($root_reason), so the slug '$folder' resolves nowhere; pass an absolute path"
      target="$root/$folder"
      ;;
  esac

  listing=""
  folder_abs="$target"
  if [ -d "$target" ]; then
    folder_abs="$({ cd "$target" && pwd -P; } 2>/dev/null)" \
      || die "$ERR_FOLDER" "'$target' could not be resolved"
    check_args=("$folder_abs")
    [ "$others" -eq 0 ] || check_args=(--others "$folder_abs")
    rc=0
    listing="$("$_self_dir/folder-sessions.sh" "${check_args[@]}" 2>/dev/null)" || rc=$?
    [ "$rc" -eq 0 ] \
      || die "$ERR_SESSIONS" "the sessions of $folder_abs could not be read, so the verdict is unknown"
  fi
  folder_name="${folder_abs##*/}"

  verdict="launch"
  next="/launch-agent \"$folder_abs\""
  holders=""
  first=1
  while IFS=$'\t' read -r h_sid h_job h_name h_state; do
    [ -n "$h_sid" ] || continue
    who="other"
    if [ "$h_sid" = "$self_id" ] \
        || { [ -n "$self_first" ] && [ "$h_job" = "${self_first:0:8}" ]; }; then
      who="this"
    fi
    holders="${holders}Holder: $h_sid $h_job $h_state $who $h_name"$'\n'
    [ "$first" -eq 1 ] || continue
    first=0
    short="$h_job"
    [ "$short" != "-" ] || short="${h_sid:0:8}"
    case "$h_state" in
      ended)
        verdict="resume"
        next="/resume-agent \"$folder_abs\""
        ;;
      retired)
        verdict="attach"
        next="claude attach $short"
        ;;
      running)
        if [ "$h_name" = "$folder_name" ]; then
          verdict="running"
          if [ "$who" = "this" ]; then
            next="nothing; this session holds the folder"
          elif [ "$h_job" != "-" ]; then
            next="claude attach $short"
          else
            next="open the terminal where session $short runs"
          fi
        else
          verdict="rename"
          if [ "$who" = "this" ]; then
            next="/rename-agent"
          elif [ "$h_job" != "-" ]; then
            next="open session $short (claude attach $short), and run /rename-agent in it"
          else
            next="open the terminal where session $short runs, and run /rename-agent in it"
          fi
        fi
        ;;
    esac
  done <<LISTING
$listing
LISTING

  printf 'Verdict: %s\n' "$verdict"
  printf 'Folder: %s\n' "$folder_abs"
  printf '%s' "$holders"
  printf 'Next: %s\n' "$next"
  exit 0
fi

# ============================================================================
# The current session
# ============================================================================
[ -n "$self_id" ] \
  || die "$ERR_NO_SESSION" "CLAUDE_CODE_SESSION_ID is not set, so there is no current session; pass a folder"

bound=""
bound_reason=""
if ! _issue_context_session_file_read bound bound_reason; then
  [ "$bound_reason" = "none" ] \
    || die "$ERR_SESSION_FILE" "the session file of $self_id could not be read ($bound_reason)"
  [ "$check" -eq 0 ] || exit 0
  printf 'Verdict: unbound\n'
  printf 'Session: %s\n' "$self_id"
  printf 'Next: /launch-agent "<folder>", or /set-work-folder "<folder>", to bind this session to a folder\n'
  exit 0
fi
folder_name="${bound##*/}"

if [ "$title_set" -eq 0 ]; then
  if ! live="$(claude agents --json 2>/dev/null)" \
      || ! printf '%s' "$live" | jq -e 'type == "array"' >/dev/null 2>&1; then
    die "$ERR_SESSIONS" "claude agents --json failed, so the name of this session is unknown"
  fi
  title="$(printf '%s' "$live" | jq -r --arg id "$self_id" \
    'first(.[] | select(.sessionId == $id) | .name | strings) // empty')"
fi

named=""
if [ "$title" = "$folder_name" ]; then
  verdict="running"
else
  named="$(folder_of_slug "$title")"
  if [ -n "$named" ] && [ "$named" != "$bound" ]; then
    verdict="moved"
  else
    named=""
    verdict="rename"
  fi
fi

if [ "$check" -eq 1 ]; then
  [ "$verdict" != "running" ] || exit 0
  if [ -n "$title" ]; then
    why="this session runs under the name '$title'"
  else
    why="this session has no name"
  fi
  if [ "$verdict" = "moved" ]; then
    printf 'moved: %s, the folder name of %s, but its work folder is %s; to work on %s in this session, run /launch-agent "%s"; to keep %s, run /rename-agent, which gives this session the name %s\n' \
      "$why" "$named" "$bound" "$named" "$named" "$bound" "$folder_name"
  else
    printf 'rename: %s, but its work folder is %s; to give this session the name %s, run /rename-agent; to work on another folder in this session, run /launch-agent "<that folder>"\n' \
      "$why" "$bound" "$folder_name"
  fi
  exit 1
fi

printf 'Verdict: %s\n' "$verdict"
printf 'Session: %s\n' "$self_id"
printf 'Name: %s\n' "${title:-none}"
printf 'Folder: %s\n' "$bound"
case "$verdict" in
  running)
    printf 'Next: nothing; the name of this session is its folder name\n'
    ;;
  moved)
    printf 'Named: %s\n' "$named"
    printf 'Next: /launch-agent "%s"\n' "$named"
    printf 'Or: /rename-agent, to keep %s and its name %s\n' "$bound" "$folder_name"
    ;;
  *)
    printf 'Next: /rename-agent\n'
    printf 'Or: /launch-agent "<that folder>", to work on another folder in this session\n'
    ;;
esac
