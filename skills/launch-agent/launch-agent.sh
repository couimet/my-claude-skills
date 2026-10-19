#!/usr/bin/env bash
#
# launch-agent.sh — Start work on a topic with its folder, launch prompt, and
# name all set in one call, in this session or in a background agent.
#
# Starting work on a topic used to take four steps done by hand: create the
# topic folder, save the launch prompt into it, point the working files at
# that folder, and name the work. Each one is easy to forget, and the ones
# that are forgotten are found out later — a job named after nothing, or a
# launch prompt nobody kept. This script does all four in one call.
#
# Usage:
#   launch-agent.sh [--bg] [--take-over] <folder> <<'LAUNCH_AGENT_PROMPT_END'
#   <task prompt>
#   LAUNCH_AGENT_PROMPT_END
#
#   launch-agent.sh [--bg] [--take-over] <folder> <task prompt>
#   launch-agent.sh --help
#
#   Each flag comes before the folder, in any order. A word after the folder
#   is prompt text.
#
#   <folder>        An absolute path, used as given, or a slug naming one
#                   directory under the topic root. The topic root is the
#                   launchAgentDefaultFolder setting when it is set, and the
#                   launcher's repository root when it is not. A slug that
#                   names an existing symlink to a directory resolves to the
#                   link's target, which can sit outside that root.
#   --bg            Start a background agent. Without it, no agent starts and
#                   the calling session's working files point at the folder.
#   --take-over     Take the folder from another session that holds it. See
#                   "One session for each folder" below.
#   <task prompt>   Standard input, when no argument follows the folder and
#                   standard input is not a terminal. Otherwise
#                   the rest of the arguments. A single argument with no
#                   whitespace that names a readable file contributes that
#                   file's content instead.
#
# Standard input is the main form because the shell changes nothing between a
# quoted heredoc marker and its end line, so URLs, slash commands, and
# apostrophes all arrive as typed, and no part of the prompt is an argument
# that could look like a file path.
#
# Two modes, because two different intentions reach this script. The default
# starts no agent. It runs every refusal, creates the folder, saves the prompt,
# and then points the calling session's own working files at the folder, so the
# session that ran the script is the session that does the work. --bg starts a
# background agent, and the calling session does not become that agent: it
# stays where it is while the work runs somewhere else.
#
# The name is always the folder's basename. In the background mode it reaches
# `claude --bg --name`. In the default mode this script cannot set it: Claude
# Code gives no documented way for a script or a hook to rename a session, so
# the script prints the /rename command for the user to type.
#
# A background launch has a depth limit. A session the user started is depth
# 0, and each background agent sits one level below the session that started
# it. --bg refuses with L006 when the new agent would go past the
# launchAgentMaxDepth setting (default 2), because nothing else stops a chain
# of agents that start agents. The depth travels in a record keyed by the job
# id, written right after the dispatch; agent-depth.sh says why. The default
# mode starts no agent, so it has no depth check.
#
# One session for each folder. Before anything is written, the script asks
# ../issue-context/folder-sessions.sh which sessions claim an existing folder.
# When another session in the state running or retired holds it, the launch
# stops with L007, which names that session and the /resume-agent command
# that continues it. In the --bg mode the calling session counts too: a
# background agent in the folder of its caller makes two sessions in one
# folder, so L007 tells the user to launch into another folder or to do the
# work in this session, and --take-over does not apply to the caller.
# --take-over takes the folder from another session through
# set-work-folder.sh --take-over: in the default mode this script runs it, and
# in the --bg mode the child runs it as its first action, so a dispatch that
# fails leaves the claim of the other session. Neither stops the other
# session; stderr gives the claude stop command. A session that ended does not hold the folder, and it
# keeps the /resume-agent hint. When the check cannot run, the launch goes on
# and one stderr line says so.
#
# No claude flag passes through to the child. The child starts with the user's
# default settings, and wanting a different model or permission mode is a
# settings change rather than a launcher argument.
#
# The child prompt is this preamble, a blank line, then the task prompt
# unchanged:
#
#   Your work folder is <folder>. As your first action, run:
#
#   ~/.claude/skills/issue-context/set-work-folder.sh '<folder>' '<name>'
#
#   Then read <cwd>/CLAUDE.md and follow it. Your launch prompt is already
#   saved at <folder>/prompt-new-agent-launch.txt, so do not write it again.
#
# The saved path is prompt-new-agent-launch.txt on the first launch into a
# folder, and a dated prompt-new-agent-launch.txt.update-<stamp>.txt on each
# later one. The CLAUDE.md sentence appears only when that file exists. The name is
# passed to set-work-folder.sh explicitly even though the script can read one
# from the job state file, because the explicit form does not depend on an
# undocumented internal file.
#
# Every check that can refuse runs before anything is written, so a refusal
# leaves no folder and no file behind. The prompt is saved before dispatch, so
# it survives a launch that fails and a child that crashes on its first turn.
#
# Output (stdout): the resolved folder first, so a typo shows in the first
# line, then the prompt file and the name. When a session that ended claimed
# the folder, one stderr line points to /resume-agent. A launch that repeats the newest
# prompt adds one Repeat: line before the prompt file. The default mode ends
# with one line saying that no agent was started and one line with the /rename
# command; --bg ends with the job id and the attach command. The job id is the
# field between the first two `·` separators of the first line claude --bg
# prints. When that field is not one plain token, the script stops with L004,
# says the agent already runs, and shows what claude --bg printed.
#
# Exit codes:
#   0  — this session was pointed at the folder, or --bg dispatched the agent
#   1  — error (see stderr)

set -euo pipefail

readonly ERR_USAGE="L001"
readonly ERR_FOLDER="L002"
readonly ERR_PROMPT="L003"
readonly ERR_DISPATCH="L004"
readonly ERR_HERE="L005"
readonly ERR_DEPTH="L006"
readonly ERR_HELD="L007"

# The one fixed filename this script owns. A launch prompt is found by name
# rather than by search, so the name does not vary and is not configurable.
readonly PROMPT_BASENAME="prompt-new-agent-launch"

usage() {
  cat <<'EOF'
Usage: launch-agent.sh [--bg] [--take-over] <folder> <<'LAUNCH_AGENT_PROMPT_END'
       <task prompt>
       LAUNCH_AGENT_PROMPT_END
       launch-agent.sh [--bg] [--take-over] <folder> <task prompt>
       launch-agent.sh --help

  <folder>       Absolute path, or a slug naming one directory under the
                 launchAgentDefaultFolder setting, else the repository root
  --bg           Start a background agent; without it, point the calling
                 session's working files at the folder
  --take-over    Take the folder from another session that holds it
  <task prompt>  Standard input, or the rest of the arguments. A single
                 argument with no whitespace naming a readable file
                 contributes that file's content instead.
  --help         Show this help message
EOF
}

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/slugify.sh"
# shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/issue-settings.sh"
# shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/topic-root.sh"
# shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/session-file.sh"
# shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/agent-depth.sh"

die() {
  echo "launch-agent $1 error: $2" >&2
  exit 1
}

# _launch_agent_normalize <text> — print <text> with case and punctuation
# removed, which is the form the near-match guard compares.
#
# Composed on _issue_context_slugify rather than written again: that function
# is the one definition of how free-form text becomes a name, and it gets all
# the way to this form except for the hyphens it inserts between runs. Two
# copies of a normalisation rule drift, and the drift is invisible, because
# both keep producing plausible answers.
_launch_agent_normalize() {
  local norm
  norm="$(_issue_context_slugify "$1")"
  printf '%s' "${norm//-/}"
}

# _launch_agent_shquote <value> — print <value> as one single-quoted shell word,
# with an embedded apostrophe escaped as '\''.
#
# The commands this script prints on failure are meant to be pasted and run, and
# English prose carries apostrophes, so a value wrapped in literal single quotes
# stops being one word the moment it holds one. Single quotes rather than
# printf %q: the dispatch fallback prints the whole composed child prompt, and
# %q collapses that multi-line string into one $'...' line nobody can read
# before pasting it.
_launch_agent_shquote() {
  local value="$1"
  local apostrophe="'"
  local escaped="'\\''"
  printf "'%s'" "${value//"$apostrophe"/$escaped}"
}

# --- Parse arguments ---
# One grammar, the one each script of the collection uses: the flags first,
# in any order, then the folder, then the prompt. A word after the folder is
# prompt text, never a flag, except --bg or --take-over in the first place
# after it: that is the order this script took before, so it stops with a
# message that gives the new form. --name and --here are refused by name for
# the same reason: a saved command from before their removal fails with a
# message that says what to do instead.
bg_mode=0
take_over=0
while :; do
  case "${1-}" in
    --help)
      usage
      exit 0
      ;;
    --bg)
      bg_mode=1
      shift
      ;;
    --take-over)
      take_over=1
      shift
      ;;
    --name)
      die "$ERR_USAGE" "--name was removed; the name is always the folder's basename"
      ;;
    --here)
      die "$ERR_USAGE" "--here was removed; this session adopting the folder is now the default, and --bg starts an agent instead"
      ;;
    -*)
      die "$ERR_USAGE" "unknown flag '$1'"
      ;;
    *)
      break
      ;;
  esac
done

if [ -z "${1-}" ]; then
  usage >&2
  die "$ERR_USAGE" "a folder is required"
fi
folder="$1"
shift

case "${1-}" in
  --bg | --take-over)
    die "$ERR_USAGE" "'$1' comes after the folder; each flag now comes before it: launch-agent.sh $1 $folder ..."
    ;;
esac

# --- Read the prompt from standard input ---
# Only when no argument is left, so an explicit argument always wins and a
# terminal is never read. Read here, among the argument checks, so an empty
# stdin gets the same refusal as no prompt at all, before anything is written.
prompt_from_stdin=0
if [ "$#" -eq 0 ] && [ ! -t 0 ]; then
  prompt="$(cat)"
  [ -z "$prompt" ] || prompt_from_stdin=1
fi

[ "$#" -ge 1 ] || [ "$prompt_from_stdin" -eq 1 ] || die "$ERR_USAGE" "a task prompt is required"

# The default mode adopts the folder for the session that ran this script, and
# set-work-folder.sh identifies that session by CLAUDE_CODE_SESSION_ID. Checked
# here, among the argument errors, so a launch outside a Claude Code session is
# refused before it creates a folder that nothing would then point at.
if [ "$bg_mode" -eq 0 ] && [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
  die "$ERR_HERE" "this session cannot adopt the folder: CLAUDE_CODE_SESSION_ID is not set, so there is no session to point at it; pass --bg to start an agent instead"
fi

# The depth limit, among the argument checks, so a refused launch leaves no
# folder and no prompt file. A damaged record refuses too: the limit is the
# one hard safeguard against a chain of agents, so it never reads as 0.
if [ "$bg_mode" -eq 1 ]; then
  max_depth="$SETTINGS_LAUNCH_AGENT_MAX_DEPTH"
  depth=0
  _issue_context_agent_depth_read depth \
    || die "$ERR_DEPTH" "the agent depth record of this session ($(_issue_context_agent_depth_dir 2>/dev/null)/${CLAUDE_CODE_SESSION_ID:0:8}) cannot be read, so its depth is unknown and no background agent can start; fix or remove the record"
  if [ $((depth + 1)) -gt "$max_depth" ]; then
    die "$ERR_DEPTH" "this session runs at agent depth $depth, and launchAgentMaxDepth is $max_depth (default 2, set in $SETTINGS_FILE), so it cannot start a background agent; record the work in this session's folder instead, or raise launchAgentMaxDepth"
  fi
fi

# Trailing slashes would make the basename this script derives and the path it
# creates disagree about what they are looking at.
while [ "$folder" != "/" ] && [ "${folder%/}" != "$folder" ]; do
  folder="${folder%/}"
done

display_name="${folder##*/}"
[ -n "$display_name" ] || die "$ERR_USAGE" "'$folder' has no basename to name the work after"

# --- Resolve the folder ---
# An absolute path is an explicit choice: it skips the shape check and the
# near-match guard, which is also the documented way past a refusal when two
# nearly identical topic names are both wanted.
case "$folder" in
  /*) # kcov-exclude-line
    target="$folder"
    ;;
  *)
    # A slug is one name, not a path. Letting mkdir -p decide the shape would
    # accept "team/onboarding" by accident and "../../tmp/x" on purpose, and
    # the guard below has no obvious meaning for either.
    case "$folder" in
      */*)
        die "$ERR_FOLDER" "'$folder' is not a single path component; pass an absolute path to reach a nested directory"
        ;;
      . | ..)
        die "$ERR_FOLDER" "'$folder' is not a topic name; pass an absolute path to reach a directory outside the topic root"
        ;;
    esac

    # The setting wins, so a launch from a session in a code repository still
    # lands in the topic repository. A bad value refuses rather than falling
    # back: the fall-back is the git root, which is the code repository this
    # setting exists to avoid. topic-root.sh owns the rule; the messages stay
    # here, because each caller names its own fix.
    root=""
    root_reason=""
    if ! _issue_context_topic_root root root_reason; then
      case "$root_reason" in
        settings)
          die "$ERR_FOLDER" "the settings file $SETTINGS_FILE could not be read, so launchAgentDefaultFolder is unknown; fix the file, or pass an absolute path as the folder" ;;
        relative)
          die "$ERR_FOLDER" "launchAgentDefaultFolder in $SETTINGS_FILE is '$SETTINGS_LAUNCH_AGENT_DEFAULT_FOLDER', which is not an absolute path; set it to an absolute path, or pass an absolute path as the folder" ;;
        missing)
          die "$ERR_FOLDER" "launchAgentDefaultFolder in $SETTINGS_FILE is '$SETTINGS_LAUNCH_AGENT_DEFAULT_FOLDER', which is not an existing directory; create it, fix the setting, or pass an absolute path as the folder" ;;
        *)
          die "$ERR_FOLDER" "not inside a git repository, so a slug has no root to resolve against; set launchAgentDefaultFolder or pass an absolute path instead" ;;
      esac
    fi
    target="$root/$folder"

    # Catch agent-launch-skill against agent_launch_skill, which mkdir -p
    # would otherwise turn into a second topic nobody meant to start. An exact
    # match is not a refusal: launching another agent into an existing topic
    # is the ordinary case. Directories only, because a topic is a directory
    # and refusing a slug over a regular file at the root would refuse
    # something nobody created as a topic.
    slug_norm="$(_launch_agent_normalize "$folder")"
    for entry in "$root"/*; do
      [ -d "$entry" ] || continue
      sibling="${entry##*/}"
      [ "$sibling" != "$folder" ] || continue
      if [ "$(_launch_agent_normalize "$sibling")" = "$slug_norm" ]; then
        die "$ERR_FOLDER" "'$folder' nearly matches the existing '$sibling' in $root; pass an absolute path if a second topic is what you want"
      fi
    done
    ;;
esac

# --- Resolve the prompt ---
# A prompt read from standard input is used as read, except that the read
# drops trailing newlines and the save adds exactly one back. Otherwise one
# argument with no whitespace that names a readable file carries a long prompt
# without shell quoting, and one such argument that looks like a path and
# names nothing is a typo: without this refusal the launch succeeds and the
# child's whole prompt is the mistyped path, which is only found out minutes
# later in its transcript. An argument that holds whitespace is prose, never a
# path, so a sentence that quotes a URL or a slash command passes through. A
# bare URL as the whole prompt still refuses; standard input is the fix.
if [ "$prompt_from_stdin" -eq 1 ]; then
  :
elif [ "$#" -eq 1 ]; then
  token="$1"
  case "$token" in
    *[[:space:]]*)
      prompt="$token"
      ;;
    *)
      if [ -f "$token" ] && [ -r "$token" ]; then
        prompt="$(cat "$token")"
      else
        case "$token" in
          */* | *.txt | *.md | *.json)
            die "$ERR_PROMPT" "'$token' looks like a file path but names no readable file; pass the prompt on standard input if it is prompt text"
            ;;
        esac
        prompt="$token"
      fi
      ;;
  esac
else
  prompt="$*"
fi

[ -n "$prompt" ] || die "$ERR_PROMPT" "the task prompt is empty"

# --- One session for each folder ---
# See the header. A folder that does not exist yet has no session. The hint
# for a session that ended is printed after the Folder line.
earlier_hint=""
held_files=()
if [ -d "$target" ] && held_abs="$({ cd "$target" && pwd -P; } 2>/dev/null)"; then
  check_args=("$held_abs")
  [ "$bg_mode" -eq 1 ] || check_args=(--others "$held_abs")
  self_first=""
  _issue_context_job_first_id self_first || self_first=""
  check_rc=0
  check_out="$("$_self_dir/../issue-context/folder-sessions.sh" "${check_args[@]}" 2>&1)" || check_rc=$?
  if [ "$check_rc" -ne 0 ]; then
    check_why="${check_out##*$'\n'}"
    check_why="${check_why#*error: }"
    echo "launch-agent: could not check whether another session holds $held_abs (${check_why:-no reason given}); the launch goes on" >&2
  else
    while IFS=$'\t' read -r h_sid h_job h_name h_state; do
      [ -n "$h_sid" ] || continue
      if [ "$h_state" = "ended" ]; then
        [ -n "$earlier_hint" ] \
          || earlier_hint="launch-agent: session ${h_sid:0:8} used this folder before; to continue that session rather than start with no context, use /resume-agent $held_abs"
        continue
      fi
      case "$h_state" in running | retired) ;; *) continue ;; esac
      if [ "$h_sid" = "${CLAUDE_CODE_SESSION_ID:-}" ] \
          || { [ -n "$self_first" ] && [ "$h_job" = "${self_first:0:8}" ]; }; then
        die "$ERR_HELD" "this session holds $held_abs, and a background agent in it would make two sessions in one folder; launch the agent into another folder, or do the work in this session"
      fi
      h_label="session $h_sid ($h_state"
      [ "$h_job" = "-" ] || h_label="$h_label, job $h_job"
      [ "$h_name" = "-" ] || h_label="$h_label, name '$h_name'"
      h_label="$h_label)"
      [ "$take_over" -eq 1 ] \
        || die "$ERR_HELD" "$h_label holds $held_abs, and two sessions in one folder each see half of the work; to continue that session, use /resume-agent $held_abs; to take the folder from it, launch again with --take-over"
      held_files+=("$h_sid	$h_job	$h_label")
    done <<HOLDERS
$check_out
HOLDERS
  fi
fi

# --- Create the folder ---
# Created rather than refused, unlike set-work-folder.sh: this call is what
# starts a topic, so the folder not existing yet is the normal case rather
# than the sign of a typo. The shape checks above are what catch the typo.
if [ -e "$target" ] && [ ! -d "$target" ]; then
  die "$ERR_FOLDER" "'$target' exists and is not a directory"
fi
mkdir -p "$target" || die "$ERR_FOLDER" "could not create $target"
# pwd -P resolves symlinks, so a slug that names an existing symlink to a
# directory reports the link's target, which can sit outside the repository
# root. That is left to stand rather than refused: a symlinked topic folder is
# something the user arranged on purpose, and the resolved folder is the first
# line this script prints, so the reader sees where the topic actually landed.
folder_abs="$({ cd "$target" && pwd -P; } 2>/dev/null)" \
  || die "$ERR_FOLDER" "'$target' could not be resolved"

printf 'Folder: %s\n' "$folder_abs"

# --- Point to an earlier session of the folder ---
# A hint, never a refusal. A session that ended in this folder holds the chat
# context of the earlier rounds, and /resume-agent continues it, where this
# launch starts with none. This script cannot tell why a new one is wanted,
# so it says so once and goes on. Only the newest one is named;
# /resume-agent picks the same one.
[ -z "$earlier_hint" ] || echo "$earlier_hint" >&2

# --- Save the prompt ---
# Before dispatch, so the file exists even when the launch fails. The stable
# name holds the first launch, because the first prompt is what defines the
# topic and what readers look for. Each later launch adds a file stamped with
# the launch time, and no launch renames, rewrites, or deletes a file that
# exists. A launch that repeats the newest prompt byte for byte adds nothing,
# so a retry leaves no trace.
#
# A later name starts with the full name of the first prompt, extension
# included: prompt-new-agent-launch.txt.update-<stamp>.txt. A name sorts before
# every longer name that starts with it, so the first prompt lists first and
# the later prompts follow in stamp order, in every locale and explorer. That
# is one rule for every file that iterates on a source file in its folder.
# Before this rule the later name was prompt-new-agent-launch.update-<stamp>.txt,
# which also sorted after the first prompt, but only because "u" sorts after
# "t". No file of that form is renamed. A folder that holds both forms lists
# its new-form files before its old-form files, which is the accepted cost.
#
# The newest prompt is therefore found by stamp, never by glob order: in a
# folder with both forms the glob lists the new form first, so its last file
# is not the newest. A suffix that is not a YYYYMMDD-HHMMSS stamp does not
# count, so a file a person named by hand is never compared.
#
# A taken stamp waits for the next second rather than taking a suffix, because
# "<stamp>-001.txt" sorts before "<stamp>.txt" and breaks the launch order. A
# stamp is taken when a file of either form holds it. noclobber makes each
# write fail rather than replace a file that appeared after the name check, so
# a race between two launches cannot break the rule.
first_prompt="$folder_abs/$PROMPT_BASENAME.txt"
prompt_file="$first_prompt"
repeat_of=""
if [ -f "$first_prompt" ]; then
  newest="$first_prompt"
  newest_stamp=""
  # With no update file a pattern stays literal, and -f skips it.
  for candidate in "$folder_abs/$PROMPT_BASENAME".update-*.txt \
    "$folder_abs/$PROMPT_BASENAME".txt.update-*.txt; do
    [ -f "$candidate" ] || continue
    candidate_stamp="${candidate##*.update-}"
    candidate_stamp="${candidate_stamp%.txt}"
    [[ "$candidate_stamp" =~ ^[0-9]{8}-[0-9]{6}$ ]] || continue
    # The stamps have one fixed width, so a byte comparison is a time
    # comparison.
    if [[ "$candidate_stamp" > "$newest_stamp" ]]; then
      newest="$candidate"
      newest_stamp="$candidate_stamp"
    fi
  done
  if printf '%s\n' "$prompt" | cmp -s - "$newest"; then
    prompt_file="$newest"
    repeat_of="$newest"
  else
    attempt=1
    while :; do
      stamp="$(date +%Y%m%d-%H%M%S)" \
        || die "$ERR_PROMPT" "could not read the clock to name the new prompt file"
      prompt_file="$folder_abs/$PROMPT_BASENAME.txt.update-$stamp.txt"
      [ -e "$prompt_file" ] || [ -e "$folder_abs/$PROMPT_BASENAME.update-$stamp.txt" ] || break
      [ "$attempt" -lt 3 ] \
        || die "$ERR_PROMPT" "no free name for a new prompt file in $folder_abs after $attempt tries; launch again in a second"
      attempt=$((attempt + 1))
      sleep 1
    done
  fi
fi
if [ -n "$repeat_of" ]; then
  printf 'Repeat: the prompt matches %s, so no new file was written.\n' "$repeat_of"
else
  (
    set -o noclobber
    printf '%s\n' "$prompt" > "$prompt_file"
  ) || die "$ERR_PROMPT" "could not write $prompt_file"
fi

printf 'Prompt: %s\n' "$prompt_file"
printf 'Name: %s\n' "$display_name"

# --- Point this session at the folder, and stop ---
# No child, so no working directory to choose and no preamble to compose. The
# writer prints the session file on stdout and says what it did on stderr.
# Its stdout is dropped: this script's stdout is a list of labelled facts, and
# the facts that matter are the last lines printed here.
if [ "$bg_mode" -eq 0 ]; then
  set_work_folder="$(cd "$_self_dir/../issue-context" && pwd -P)/set-work-folder.sh"
  take_over_flag=()
  [ "$take_over" -eq 0 ] || take_over_flag=(--take-over)
  if ! "$set_work_folder" ${take_over_flag[@]+"${take_over_flag[@]}"} "$folder_abs" "$display_name" > /dev/null; then
    {
      echo "launch-agent $ERR_HERE error: the folder was not adopted. The folder and the prompt file are in place; run this to adopt it by hand:"
      echo
      take_over_text=""
      [ "$take_over" -eq 0 ] || take_over_text="--take-over "
      printf '%s %s%s %s\n' "$(_launch_agent_shquote "$set_work_folder")" "$take_over_text" \
        "$(_launch_agent_shquote "$folder_abs")" "$(_launch_agent_shquote "$display_name")"
    } >&2 # kcov-exclude-line
    exit 1
  fi
  printf 'Here: no agent was started; this session now writes its working files to %s\n' "$folder_abs"
  # The session keeps the automatic name Claude Code gave it, and only the
  # user can change that, so the last line is the command to type.
  printf 'Type /rename %s to give this session the folder name.\n' "$display_name"
  exit 0
fi

# --- Choose the child's working directory ---
# The repository root that contains the folder, so that repository's CLAUDE.md
# loads in the child. A folder in no repository is its own working directory.
child_cwd="$(git -C "$folder_abs" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$child_cwd" ] || child_cwd="$folder_abs"

# --- Compose the child prompt ---
# With --take-over, the child removes the files of the other session when it
# claims the folder, so a dispatch that fails leaves that session's claim.
child_take_over=""
[ "$take_over" -eq 0 ] || child_take_over=" --take-over"
child_prompt="Your work folder is $folder_abs. As your first action, run:

~/.claude/skills/issue-context/set-work-folder.sh$child_take_over $(_launch_agent_shquote "$folder_abs") $(_launch_agent_shquote "$display_name")

"
if [ -f "$child_cwd/CLAUDE.md" ]; then
  child_prompt="${child_prompt}Then read $child_cwd/CLAUDE.md and follow it. "
fi
child_prompt="${child_prompt}Your launch prompt is already saved at $prompt_file, so do not write it again.

$prompt"

# --- Dispatch ---
if ! job_id="$({ cd "$child_cwd" && claude --bg --name "$display_name" "$child_prompt"; })"; then
  {
    echo "launch-agent $ERR_DISPATCH error: the launch failed. The folder and the prompt file are in place; run this from $child_cwd to launch by hand:"
    echo
    printf 'claude --bg --name %s %s\n' "$(_launch_agent_shquote "$display_name")" \
      "$(_launch_agent_shquote "$child_prompt")"
  } >&2 # kcov-exclude-line
  exit 1
fi

# --- Report the take-over ---
# The child takes the folder when it runs set-work-folder.sh, which can be
# after this script exits, so the line says the take-over was dispatched.
for held in ${held_files[@]+"${held_files[@]}"}; do
  IFS=$'\t' read -r h_sid h_job h_label <<HELD
$held
HELD
  if [ "$h_job" = "-" ]; then
    h_stop="close that session"
  else
    h_stop="stop it with claude stop $h_job"
  fi
  echo "launch-agent: takeover dispatched for $folder_abs from $h_label; it can still write to the folder until it stops: $h_stop" >&2
done

# --- Read the job id ---
# claude --bg prints a status line, `backgrounded · <id> · <name>`, then hint
# lines, and it can wrap parts of them in ANSI codes even when its output goes
# into a pipe. The id is the field between the first two separators of the
# first line once the codes are gone. Both kinds of sequence go: CSI for color,
# and OSC, which a terminal hyperlink uses. An id that is not one plain token
# means the layout changed, and a wrong Attach: line is worse than none.
esc=$'\033'
bel=$'\007'
launch_output="$(printf '%s\n' "$job_id" | LC_ALL=C sed -E \
  -e "s#${esc}[]][^${bel}${esc}]*(${bel}|${esc}\\\\)##g" \
  -e "s#${esc}[[][0-?]*[ -/]*[@-~]##g")"
first_line="${launch_output%%$'\n'*}"
job_id=""
case "$first_line" in
  *·*·*)
    job_id="${first_line#*·}"
    job_id="${job_id%%·*}"
    job_id="${job_id#"${job_id%%[![:space:]]*}"}"
    job_id="${job_id%"${job_id##*[![:space:]]}"}"
    ;;
esac

# The agent already runs here, so this failure must not offer the relaunch
# command the dispatch failure above prints: running it starts a second agent.
if ! [[ "$job_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
  {
    echo "launch-agent $ERR_DISPATCH error: the agent started as $display_name, but its job id could not be read. Run claude agents to find it, and do not launch it again: that starts a second agent."
    echo
    if [ -n "$launch_output" ]; then
      echo "claude --bg printed:"
      printf '%s\n' "$launch_output" | sed 's/^/  /'
    else
      echo "claude --bg printed nothing."
    fi
  } >&2 # kcov-exclude-line
  exit 1
fi

# --- Record the child's depth ---
# The job id is the first 8 characters of the child's session id, which is
# what the child reads its record by. A record that could not be written
# leaves the child at depth 0 in its own eyes, which lifts the limit for its
# chain, so the failure says how to stop it.
if ! _issue_context_agent_depth_write "$job_id" $((depth + 1)); then
  {
    echo "launch-agent $ERR_DEPTH error: the agent started as $display_name (job $job_id), but its depth record could not be written under $(_issue_context_agent_depth_dir 2>/dev/null), so the depth limit does not apply to it. Stop it with claude stop $job_id if it must not start agents of its own. Do not launch it again: that starts a second agent."
  } >&2 # kcov-exclude-line
  exit 1
fi

printf 'Job: %s\n' "$job_id"
printf 'Attach: claude attach %s\n' "$job_id"
