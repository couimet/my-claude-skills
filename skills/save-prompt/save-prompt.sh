#!/usr/bin/env bash
#
# save-prompt.sh — Save a prompt verbatim in the prompts/ folder of a work
# folder, so no model copies the text by hand.
#
# Usage:
#   save-prompt.sh [--kind launch|next|saved] [--from transcript]
#   save-prompt.sh [--kind launch|next|saved] --from stdin <folder>
#   save-prompt.sh --help
#
#   --kind   launch: a prompt that starts or relaunches a session of the
#            folder. next: a prompt that a session runs later, such as after
#            a /clear. saved: a prompt that a person asks to keep. The
#            default is saved.
#   --from   transcript (the default) reads the text from the transcript of
#            this session. stdin reads it from standard input, and takes the
#            folder as its one argument. An explicit mode, because a script
#            that reads standard input when nobody meant it waits on a
#            terminal.
#   <folder> stdin mode only: an absolute path to an existing directory.
#
# The file is <folder>/prompts/<YYYYMMDD-HHMMSS>-<kind>.txt. The stamp is the
# local time of the write, and the name has no slug. The first launch prompt
# of a folder is the oldest prompts/*-launch.txt. The script makes prompts/
# when it is missing, and it writes only the prompt file.
#
# Transcript mode. The session id comes from CLAUDE_CODE_SESSION_ID. The
# work folder comes from the session file of the session, through the reader
# of ../issue-context/session-file.sh; with no session file the script
# refuses and names /set-work-folder, and it never guesses a folder. The
# transcript is the first match of the glob <projects dir>/*/<session id>.jsonl,
# where the projects dir is SAVE_PROMPT_PROJECTS_DIR, else
# ${CLAUDE_CONFIG_DIR:-~/.claude}/projects. A glob by the session id does not
# depend on the cwd, so a cd during the session does no harm.
#
# Message selection, from the entries in transcript order:
#   - A human message is a `type: user` entry with `origin.kind: human`.
#     Each entry of another origin.kind, such as a message from a peer
#     session or a task notification, is skipped.
#   - The script saves the newest human message. When that message is a bare
#     /save-prompt, with no text after it, the script saves the human message
#     before it.
#   - A message that the person sends while a turn runs is an `attachment`
#     entry of type `queued_command` with `attachment.origin.kind: human`
#     (an older form puts it at the top-level `origin.kind`). Each such
#     entry after the saved message, up to the next human message, follows
#     the saved text under the line
#     `--- Follow-up message in the same turn ---`.
#   - A string content is the text. An array content gives its text blocks,
#     joined with a newline.
#   - A slash command is in the transcript as <command-name> and
#     <command-args> tags at the start of the content, after an optional
#     <command-message> tag. The script writes the typed form /<name> <args>.
#     The same tags in the middle of a prompt are text, saved as they are.
#   - With no human message, the script refuses: the transcript form can have
#     changed. It never writes an empty file.
#
# Stdin mode writes the bytes of standard input as they are.
#
# Writes. A byte-for-byte repeat of the newest file of the same kind writes
# nothing. For the kind launch, the newest launch prompt is the newest
# prompts/*-launch.txt; when prompts/ holds none, it is the newest of the old
# names at the folder root, prompt-new-agent-launch.txt and its
# .update-<stamp>.txt files, by stamp. A stamp is taken when any file in
# prompts/ starts with it, of any kind, so each stamp names one file and `ls`
# gives one total order. A taken stamp waits for the next second, at most 3
# tries. noclobber makes the write fail rather than replace a file that
# appeared after the name check.
#
# Output (stdout): one line, the absolute path of the new file, or
# `Repeat: the prompt matches <path>, so no new file was written.`
#
# Exit codes:
#   0  — the file was written, or the prompt repeats the newest file
#   1  — error (see stderr): M001 usage or empty input, M002 folder, M003 no
#        session file, M004 no transcript, M005 no human message to save,
#        M006 write

set -euo pipefail

readonly ERR_USAGE="M001"
readonly ERR_FOLDER="M002"
readonly ERR_SESSION="M003"
readonly ERR_TRANSCRIPT="M004"
readonly ERR_MESSAGE="M005"
readonly ERR_WRITE="M006"

readonly SEPARATOR="--- Follow-up message in the same turn ---"
# The old names of a launch prompt. Read only, for the repeat check of the
# kind launch: no new file takes them.
readonly OLD_LAUNCH_BASENAME="prompt-new-agent-launch"

usage() {
  cat <<'EOF'
Usage: save-prompt.sh [--kind launch|next|saved] [--from transcript]
       save-prompt.sh [--kind launch|next|saved] --from stdin <folder>
       save-prompt.sh --help

  --kind   launch, next, or saved (default saved)
  --from   transcript (default): the newest human message of this session
           stdin: the text on standard input, saved in <folder>
  --help   Show this help message
EOF
}

die() {
  echo "save-prompt $1 error: $2" >&2
  exit 1
}

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Parse arguments ---
kind="saved"
from="transcript"
folder=""
folder_count=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --kind)
      [ "$#" -ge 2 ] || die "$ERR_USAGE" "--kind requires a value: launch, next, or saved"
      kind="$2"
      shift 2
      ;;
    --from)
      [ "$#" -ge 2 ] || die "$ERR_USAGE" "--from requires a value: transcript or stdin"
      from="$2"
      shift 2
      ;;
    -*)
      die "$ERR_USAGE" "unknown flag '$1'"
      ;;
    *)
      folder="$1"
      folder_count=$((folder_count + 1))
      shift
      ;;
  esac
done
case "$kind" in
  launch | next | saved) ;; # kcov-exclude-line
  *) die "$ERR_USAGE" "unknown kind '$kind'; use launch, next, or saved" ;;
esac
case "$from" in
  transcript)
    [ "$folder_count" -eq 0 ] \
      || die "$ERR_USAGE" "transcript mode takes no folder; it reads the work folder from the session file (for a folder, use --from stdin <folder>)"
    ;;
  stdin)
    [ "$folder_count" -eq 1 ] || die "$ERR_USAGE" "--from stdin takes one folder, got $folder_count"
    ;;
  *) die "$ERR_USAGE" "unknown mode '$from'; use transcript or stdin" ;;
esac

# --- Get the folder and the text ---
text_file="$(mktemp)"
trap 'rm -f "$text_file"' EXIT

if [ "$from" = "stdin" ]; then
  case "$folder" in
    /*) ;; # kcov-exclude-line
    *) die "$ERR_FOLDER" "'$folder' is not an absolute path" ;;
  esac
  cat > "$text_file" || die "$ERR_USAGE" "could not read standard input"
else
  # Only this mode reads the settings, the session file, and the transcript,
  # so the stdin mode of launch-agent.sh needs neither jq nor a settings file.
  # shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
  source "$_self_dir/../issue-context/issue-settings.sh"
  # shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
  source "$_self_dir/../issue-context/session-file.sh"
  command -v jq >/dev/null 2>&1 \
    || die "$ERR_SESSION" "jq not found; it is required to read the session file and the transcript"
  reason=""
  if ! _issue_context_session_file_read folder reason; then
    die "$ERR_SESSION" "this session has no work folder in a session file ($reason), and the script never guesses one; run /set-work-folder <absolute folder> first"
  fi
  [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || die "$ERR_SESSION" "CLAUDE_CODE_SESSION_ID is not set, so the transcript is unknown"
  projects_dir="${SAVE_PROMPT_PROJECTS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects}"
  transcript=""
  for candidate in "$projects_dir"/*/"$CLAUDE_CODE_SESSION_ID.jsonl"; do
    [ -f "$candidate" ] && { transcript="$candidate"; break; }
  done
  [ -n "$transcript" ] \
    || die "$ERR_TRANSCRIPT" "no transcript $CLAUDE_CODE_SESSION_ID.jsonl in $projects_dir/*"

  # -R with fromjson? skips a line that is not JSON. The first output line is
  # the status: OK, then the text; NONE (no human message); or BARE (a bare
  # /save-prompt with no human message before it).
  # The kcov markers wrap the jq program: kcov counts each line of a '...'
  # program as a bash line that never runs. See scripts/shell-coverage.sh.
  selection="$(jq -R -n -r --arg sep "$SEPARATOR" ' # kcov-exclude-start
    def render:
      if type == "string" then .
      elif type == "array" then [.[] | objects | select(.type == "text") | .text | strings] | join("\n")
      else "" end;
    def typed:
      if test("^\\s*<command-(message|name)>") and test("<command-name>[^<]*</command-name>"; "s") then
        (capture("<command-name>(?<n>[^<]*)</command-name>"; "s").n | ltrimstr("/")) as $n
        | ((capture("<command-args>(?<a>[\\s\\S]*)</command-args>").a) // "") as $a
        | "/" + $n + (if ($a | test("\\S")) then " " + $a else "" end)
      else . end;
    def bare: (gsub("^\\s+|\\s+$"; "") == "/save-prompt");
    [inputs | fromjson? | objects
      | if .type == "user" and .origin.kind? == "human" then
          {k: "h", t: (.message.content | render | typed)}
        elif .type == "attachment" and .attachment.type? == "queued_command"
          and (.attachment.origin.kind? // .origin.kind?) == "human" then
          {k: "f", t: (.attachment.prompt | render | typed)}
        else empty end] as $e
    | [range(0; $e | length) | select($e[.].k == "h")] as $hs
    | if ($hs | length) == 0 then "NONE"
      else
        (if ($e[$hs[-1]].t | bare) then
           (if ($hs | length) >= 2 then $hs[-2] else null end)
         else $hs[-1] end) as $sel
        | if $sel == null then "BARE"
          else
            ([$hs[] | select(. > $sel)] | first // ($e | length)) as $end
            | "OK\n" + $e[$sel].t
              + ([range($sel + 1; $end) | select($e[.].k == "f") | "\n\n" + $sep + "\n\n" + $e[.].t] | join(""))
          end
      end
    # kcov-exclude-end
  ' "$transcript")" || die "$ERR_MESSAGE" "could not read the transcript $transcript"
  case "$selection" in
    OK$'\n'*) printf '%s\n' "${selection#OK$'\n'}" > "$text_file" ;;
    BARE) die "$ERR_MESSAGE" "the transcript $transcript holds only a bare /save-prompt, and no human message before it to save" ;;
    *) die "$ERR_MESSAGE" "the transcript $transcript holds no human message (a type: user entry with origin.kind: human); the transcript form can have changed, so nothing was written" ;;
  esac
fi

[ -d "$folder" ] || die "$ERR_FOLDER" "'$folder' is not an existing directory"
folder_abs="$({ cd "$folder" && pwd -P; } 2>/dev/null)" || die "$ERR_FOLDER" "'$folder' could not be resolved"
[ -n "$(tr -d '[:space:]' < "$text_file")" ] || die "$ERR_USAGE" "the prompt is empty, so nothing was written"

prompts_dir="$folder_abs/prompts"

# --- Find the newest file of the kind ---
# The stamps have one fixed width, so the byte order of the names in
# prompts/ is the time order.
newest=""
for candidate in "$prompts_dir"/*-"$kind".txt; do
  [ -f "$candidate" ] || continue
  base="${candidate##*/}"
  [[ "$base" =~ ^[0-9]{8}-[0-9]{6}-[a-z]+\.txt$ ]] || continue
  newest="$candidate"
done
if [ -z "$newest" ] && [ "$kind" = "launch" ] && [ -f "$folder_abs/$OLD_LAUNCH_BASENAME.txt" ]; then
  # A suffix that is not a YYYYMMDD-HHMMSS stamp does not count, so a file
  # a person named by hand is never compared.
  newest="$folder_abs/$OLD_LAUNCH_BASENAME.txt"
  newest_stamp=""
  for candidate in "$folder_abs/$OLD_LAUNCH_BASENAME".update-*.txt \
    "$folder_abs/$OLD_LAUNCH_BASENAME".txt.update-*.txt; do
    [ -f "$candidate" ] || continue
    candidate_stamp="${candidate##*.update-}"
    candidate_stamp="${candidate_stamp%.txt}"
    [[ "$candidate_stamp" =~ ^[0-9]{8}-[0-9]{6}$ ]] || continue
    if [[ "$candidate_stamp" > "$newest_stamp" ]]; then
      newest="$candidate"
      newest_stamp="$candidate_stamp"
    fi
  done
fi

if [ -n "$newest" ] && cmp -s "$text_file" "$newest"; then
  printf 'Repeat: the prompt matches %s, so no new file was written.\n' "$newest"
  exit 0
fi

# --- Write ---
mkdir -p "$prompts_dir" || die "$ERR_WRITE" "could not create $prompts_dir"
attempt=1
while :; do
  stamp="$(date +%Y%m%d-%H%M%S)" \
    || die "$ERR_WRITE" "could not read the clock to name the new prompt file"
  taken=0
  for candidate in "$prompts_dir/$stamp"-*.txt; do
    [ -e "$candidate" ] && { taken=1; break; }
  done
  [ "$taken" -eq 1 ] || break
  [ "$attempt" -lt 3 ] \
    || die "$ERR_WRITE" "no free name for a new prompt file in $prompts_dir after $attempt tries; save again in a second"
  attempt=$((attempt + 1))
  sleep 1
done
prompt_file="$prompts_dir/$stamp-$kind.txt"
(
  set -o noclobber
  cat "$text_file" > "$prompt_file"
) 2>/dev/null || die "$ERR_WRITE" "could not write $prompt_file"

printf '%s\n' "$prompt_file"
