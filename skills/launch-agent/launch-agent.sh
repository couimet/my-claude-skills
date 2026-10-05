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
#   launch-agent.sh <folder> [--bg] <<'LAUNCH_AGENT_PROMPT_END'
#   <task prompt>
#   LAUNCH_AGENT_PROMPT_END
#
#   launch-agent.sh <folder> [--bg] <task prompt>
#   launch-agent.sh --help
#
#   <folder>        An absolute path, used as given, or a slug naming one
#                   directory under the topic root. The topic root is the
#                   launchAgentDefaultFolder setting when it is set, and the
#                   launcher's repository root when it is not. A slug that
#                   names an existing symlink to a directory resolves to the
#                   link's target, which can sit outside that root.
#   --bg            Start a background agent. Without it, no agent starts and
#                   the calling session's working files point at the folder.
#   <task prompt>   Standard input, when no argument follows the folder and
#                   the flag and standard input is not a terminal. Otherwise
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
# folder, and a dated prompt-new-agent-launch.update-<stamp>.txt on each later
# one. The CLAUDE.md sentence appears only when that file exists. The name is
# passed to set-work-folder.sh explicitly even though the script can read one
# from the job state file, because the explicit form does not depend on an
# undocumented internal file.
#
# Every check that can refuse runs before anything is written, so a refusal
# leaves no folder and no file behind. The prompt is saved before dispatch, so
# it survives a launch that fails and a child that crashes on its first turn.
#
# Output (stdout): the resolved folder first, so a typo shows in the first
# line, then the prompt file and the name. A launch that repeats the newest
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

# The one fixed filename this script owns. A launch prompt is found by name
# rather than by search, so the name does not vary and is not configurable.
readonly PROMPT_BASENAME="prompt-new-agent-launch"

usage() {
  cat <<'EOF'
Usage: launch-agent.sh <folder> [--bg] <<'LAUNCH_AGENT_PROMPT_END'
       <task prompt>
       LAUNCH_AGENT_PROMPT_END
       launch-agent.sh <folder> [--bg] <task prompt>
       launch-agent.sh --help

  <folder>       Absolute path, or a slug naming one directory under the
                 launchAgentDefaultFolder setting, else the repository root
  --bg           Start a background agent; without it, point the calling
                 session's working files at the folder
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
    die "$ERR_USAGE" "unknown flag '$1'; the folder comes first"
    ;;
esac

folder="$1"
shift

bg_mode=0
# One flag remains. --name and --here are refused by name rather than read as
# the start of the prompt, so a saved command from before their removal fails
# with a message that says what to do instead.
while :; do
  case "${1-}" in
    --bg)
      bg_mode=1
      shift
      ;;
    --name)
      die "$ERR_USAGE" "--name was removed; the name is always the folder's basename"
      ;;
    --here)
      die "$ERR_USAGE" "--here was removed; this session adopting the folder is now the default, and --bg starts an agent instead"
      ;;
    *)
      break
      ;;
  esac
done

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
    # setting exists to avoid. The value expands nothing, so it is checked
    # exactly as written. A settings file that could not be read refuses for
    # the same reason: the loader then reports the setting as empty, and the
    # setting may well be in the file.
    if [ "$SETTINGS_LOAD_STATUS" = "failed" ]; then
      die "$ERR_FOLDER" "the settings file $SETTINGS_FILE could not be read, so launchAgentDefaultFolder is unknown; fix the file, or pass an absolute path as the folder"
    fi
    default_folder="$SETTINGS_LAUNCH_AGENT_DEFAULT_FOLDER"
    if [ -n "$default_folder" ]; then
      case "$default_folder" in
        /*) ;; # kcov-exclude-line
        *)
          die "$ERR_FOLDER" "launchAgentDefaultFolder in $SETTINGS_FILE is '$default_folder', which is not an absolute path; set it to an absolute path, or pass an absolute path as the folder"
          ;;
      esac
      [ -d "$default_folder" ] \
        || die "$ERR_FOLDER" "launchAgentDefaultFolder in $SETTINGS_FILE is '$default_folder', which is not an existing directory; create it, fix the setting, or pass an absolute path as the folder"
      while [ "$default_folder" != "/" ] && [ "${default_folder%/}" != "$default_folder" ]; do
        default_folder="${default_folder%/}"
      done
      root="$default_folder"
    else
      work_root="$("$_self_dir/../issue-context/claude-work-root.sh" 2>/dev/null)" \
        || die "$ERR_FOLDER" "not inside a git repository, so a slug has no root to resolve against; set launchAgentDefaultFolder or pass an absolute path instead"
      # claude-work-root.sh reports <main checkout root>/.claude-work, and it
      # is used here for the half of its job this needs: finding the main
      # checkout through a linked worktree. Topic folders sit at that root.
      root="$(dirname "$work_root")"
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

# --- Save the prompt ---
# Before dispatch, so the file exists even when the launch fails. The stable
# name holds the first launch, because the first prompt is what defines the
# topic and what readers look for. Each later launch adds a file stamped with
# the launch time, and no launch renames, rewrites, or deletes a file that
# exists. The later name continues with "update" so that the "t" of ".txt"
# sorts the first prompt ahead of it in every locale, and the digits after it
# sort the later prompts by stamp. A launch that repeats the newest prompt
# byte for byte adds nothing, so a retry leaves no trace.
#
# A taken stamp waits for the next second rather than taking a suffix, because
# "<stamp>-001.txt" sorts before "<stamp>.txt" and breaks the launch order.
# noclobber makes each write fail rather than replace a file that appeared
# after the name check, so a race between two launches cannot break the rule.
first_prompt="$folder_abs/$PROMPT_BASENAME.txt"
prompt_file="$first_prompt"
repeat_of=""
if [ -f "$first_prompt" ]; then
  newest="$first_prompt"
  # With no update file the pattern stays literal, and -f skips it.
  for candidate in "$folder_abs/$PROMPT_BASENAME".update-*.txt; do
    [ -f "$candidate" ] && newest="$candidate"
  done
  if printf '%s\n' "$prompt" | cmp -s - "$newest"; then
    prompt_file="$newest"
    repeat_of="$newest"
  else
    attempt=1
    while :; do
      stamp="$(date +%Y%m%d-%H%M%S)" \
        || die "$ERR_PROMPT" "could not read the clock to name the new prompt file"
      prompt_file="$folder_abs/$PROMPT_BASENAME.update-$stamp.txt"
      [ -e "$prompt_file" ] || break
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
  if ! "$set_work_folder" "$folder_abs" "$display_name" > /dev/null; then
    {
      echo "launch-agent $ERR_HERE error: the folder was not adopted. The folder and the prompt file are in place; run this to adopt it by hand:"
      echo
      printf '%s %s %s\n' "$(_launch_agent_shquote "$set_work_folder")" \
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
child_prompt="Your work folder is $folder_abs. As your first action, run:

~/.claude/skills/issue-context/set-work-folder.sh $(_launch_agent_shquote "$folder_abs") $(_launch_agent_shquote "$display_name")

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

printf 'Job: %s\n' "$job_id"
printf 'Attach: claude attach %s\n' "$job_id"
