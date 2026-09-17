#!/usr/bin/env bash
#
# launch-agent.sh — Dispatch a background agent with its folder, prompt file,
# and display name all set at launch.
#
# Launching a background agent on a topic used to take four steps done by
# hand: create the topic folder, save the launch prompt into it, tell the
# child to point its working files at that folder, and name the job. Each one
# is easy to forget, and the ones that are forgotten are found out later —
# a job named after nothing, or a launch prompt nobody kept. This script does
# all four in one call.
#
# Usage:
#   launch-agent.sh <folder> [--name <display-name>] [--here] <task prompt>
#   launch-agent.sh --help
#
#   <folder>        An absolute path, used as given, or a slug naming one
#                   directory under the launcher's repository root. A slug
#                   that names an existing symlink to a directory resolves
#                   to the link's target, which can sit outside that root.
#   --name          The display name the job carries in `claude agents` and in
#                   the terminal title. Defaults to the folder's basename.
#   --here          Start no agent. Point the calling session's working files at
#                   the folder instead.
#   <task prompt>   The rest of the arguments. A single argument that names a
#                   readable file contributes that file's content instead,
#                   which is how a long prompt travels without shell quoting.
#
# Two modes, because two different intentions reach this script. The default
# starts a background agent, and the calling session does not become that
# agent: it stays where it is while the work runs somewhere else. --here starts
# no agent at all. It runs every refusal, creates the folder, saves the prompt,
# and then points the calling session's own working files at the folder, so the
# session that ran the script is the session that does the work. Use --here when
# you already sit in the session you want to work in, and the default when the
# work should run without you.
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
# The CLAUDE.md sentence appears only when that file exists. The display name
# is passed to set-work-folder.sh explicitly even though the script can read
# one from the job state file, because the explicit form does not depend on an
# undocumented internal file.
#
# Every check that can refuse runs before anything is written, so a refusal
# leaves no folder and no file behind. The prompt is saved before dispatch, so
# it survives a launch that fails and a child that crashes on its first turn.
#
# Output (stdout): the resolved folder first, so a typo shows in the first
# line, then the prompt file and the display name. The default mode ends with
# the job id and the attach command; --here ends with one line saying that no
# agent was started.
#
# Exit codes:
#   0  — the agent was dispatched, or --here pointed this session at the folder
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
Usage: launch-agent.sh <folder> [--name <display-name>] [--here] <task prompt>
       launch-agent.sh --help

  <folder>       Absolute path, or a slug naming one directory under the
                 launcher's repository root
  --name         Display name for the background job (default: folder basename)
  --here         Start no agent; point the calling session's working files at
                 the folder instead
  <task prompt>  The task for the agent. A single argument naming a readable
                 file contributes that file's content instead.
  --help         Show this help message
EOF
}

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/slugify.sh"

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

# _launch_agent_mtime_stamp <file> — print <file>'s modification time as
# YYYYMMDD-HHMMSS. Returns 1 when neither stat dialect answers.
#
# The archived name is stamped from the file being archived rather than from
# now, so the stamp says when that prompt was written. BSD stat formats the
# time itself; GNU stat gives epoch seconds and GNU date formats them. The
# daily driver is macOS and CI is Linux, so both are tried.
_launch_agent_mtime_stamp() {
  local file="$1" out epoch
  if out="$(stat -f '%Sm' -t '%Y%m%d-%H%M%S' "$file" 2>/dev/null)"; then
    printf '%s' "$out"
    return 0
  fi
  if epoch="$(stat -c '%Y' "$file" 2>/dev/null)"; then
    if out="$(date -d "@$epoch" +%Y%m%d-%H%M%S 2>/dev/null)"; then
      printf '%s' "$out"
      return 0
    fi
  fi
  return 1
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

display_name=""
here_mode=0
# A loop rather than one test each: the two flags are independent, and a caller
# who writes them in the other order means the same thing.
while :; do
  case "${1-}" in
    --name)
      [ "$#" -ge 2 ] || die "$ERR_USAGE" "--name takes a display name"
      display_name="$2"
      [ -n "$display_name" ] || die "$ERR_USAGE" "--name takes a non-empty display name"
      shift 2
      ;;
    --here)
      here_mode=1
      shift
      ;;
    *)
      break
      ;;
  esac
done

[ "$#" -ge 1 ] || die "$ERR_USAGE" "a task prompt is required"

# --here adopts the folder for the session that ran this script, and
# set-work-folder.sh identifies that session by CLAUDE_CODE_SESSION_ID. Checked
# here, among the argument errors, so a --here outside a Claude Code session is
# refused before it creates a folder that nothing would then point at.
if [ "$here_mode" -eq 1 ] && [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
  die "$ERR_HERE" "--here needs CLAUDE_CODE_SESSION_ID, and it is not set, so there is no session to point at the folder; run without --here to start an agent instead"
fi

# Trailing slashes would make the basename this script derives and the path it
# creates disagree about what they are looking at.
while [ "$folder" != "/" ] && [ "${folder%/}" != "$folder" ]; do
  folder="${folder%/}"
done

[ -n "$display_name" ] || display_name="${folder##*/}"
[ -n "$display_name" ] || die "$ERR_USAGE" "'$folder' has no basename to name the job after; pass --name"

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
        die "$ERR_FOLDER" "'$folder' is not a topic name; pass an absolute path to reach a directory outside the repository root"
        ;;
    esac

    work_root="$("$_self_dir/../issue-context/claude-work-root.sh" 2>/dev/null)" \
      || die "$ERR_FOLDER" "not inside a git repository, so a slug has no root to resolve against; pass an absolute path instead"
    # claude-work-root.sh reports <main checkout root>/.claude-work, and it is
    # used here for the half of its job this needs: finding the main checkout
    # through a linked worktree. Topic folders sit at that root.
    root="$(dirname "$work_root")"
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
# One argument naming a readable file carries a long prompt without shell
# quoting. One argument that looks like a path and names nothing is a typo:
# without this refusal the launch succeeds and the child's whole prompt is the
# mistyped path, which is only found out minutes later in its transcript.
if [ "$#" -eq 1 ]; then
  token="$1"
  if [ -f "$token" ] && [ -r "$token" ]; then
    prompt="$(cat "$token")"
  else
    case "$token" in
      */* | *.txt | *.md | *.json)
        die "$ERR_PROMPT" "'$token' looks like a file path but names no readable file"
        ;;
    esac
    prompt="$token"
  fi
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
# Before dispatch, so the file exists even when the launch fails. An existing
# prompt is archived under its own modification time rather than overwritten:
# the unsuffixed name always holds the latest launch, and no earlier prompt is
# lost. Two archives can land on one stamp when their predecessors shared an
# mtime second, so a collision takes a suffix rather than the earlier file.
prompt_file="$folder_abs/$PROMPT_BASENAME.txt"
if [ -f "$prompt_file" ]; then
  stamp="$(_launch_agent_mtime_stamp "$prompt_file")" \
    || die "$ERR_PROMPT" "could not read the modification time of $prompt_file"
  rotated="$folder_abs/$PROMPT_BASENAME.$stamp.txt"
  collision=1
  while [ -e "$rotated" ]; do
    rotated="$(printf '%s/%s.%s-%03d.txt' "$folder_abs" "$PROMPT_BASENAME" "$stamp" "$collision")"
    collision=$((collision + 1))
  done
  mv "$prompt_file" "$rotated" \
    || die "$ERR_PROMPT" "could not archive $prompt_file, so the earlier prompt would have been overwritten"
fi
printf '%s\n' "$prompt" > "$prompt_file" \
  || die "$ERR_PROMPT" "could not write $prompt_file"

printf 'Prompt: %s\n' "$prompt_file"
printf 'Name: %s\n' "$display_name"

# --- Point this session at the folder, and stop ---
# No child, so no working directory to choose and no preamble to compose. The
# writer prints the session file on stdout and says what it did on stderr.
# Its stdout is dropped: this script's stdout is a list of labelled facts, and
# the fact that matters is the last line printed here.
if [ "$here_mode" -eq 1 ]; then
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

job_id="$(printf '%s' "$job_id" | tr -d '[:space:]')"
[ -n "$job_id" ] || die "$ERR_DISPATCH" "the launch reported no job id, so there is nothing to attach to"

printf 'Job: %s\n' "$job_id"
printf 'Attach: claude attach %s\n' "$job_id"
