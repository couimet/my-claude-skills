#!/usr/bin/env bash
#
# fork-side-item.sh — Move one side item out of the calling session: create a
# side folder for it under the topic root, and start a background worker there
# that owns the item until it closes the folder.
#
# A side item is a problem a session finds outside its own task: a defect, a
# smell, a gap in the docs. Kept in the work folder of the task, it mixes
# steps that do not belong together, and nobody owns it once the task ends.
#
# Usage:
#   fork-side-item.sh fork <claim> <<'FORK_SIDE_ITEM_PROMPT_END'
#   <worker prompt>
#   FORK_SIDE_ITEM_PROMPT_END
#
#   fork-side-item.sh list
#   fork-side-item.sh --help
#
#   fork   Name the folder side-<slug>, where the slug comes from <claim> and
#          is cut at 50 characters, and start the worker through
#          launch-agent.sh <folder> --bg with the worker prompt from standard
#          input. launch-agent.sh creates the folder, saves the prompt as
#          prompt-new-agent-launch.txt, names the worker after the folder, and
#          applies the depth limit. This script adds no folder code of its own.
#   list   Print one "<folder><TAB><state>" line for each side-* directory
#          under the topic root. The state is the outcome in the folder's
#          side-outcome.txt, or "open" when the worker has not closed it.
#
# The fixed prefix side- lets one glob find every side item. It is a one-way
# door: notes cite a side folder by its path, so a later rename breaks each
# citation. It is not side-quest-, which /start-side-quest uses for branches.
#
# A side folder that exists already is refused (F002), with its state, rather
# than launched into. Two claims can give the same slug, and a fork of an item
# already forked is the common case: the refusal stops a second worker that
# would not know about the first. The calling session rewords the claim when
# the items differ.
#
# The close record, side-outcome.txt, is one line: <outcome><TAB><link or
# reason>. <outcome> is ticket, enrich, message, or drop. The worker writes it;
# this script only reads its first field. A later field adds a column at the
# end, and a later outcome adds to the set.
#
# Output (stdout) of fork: the lines launch-agent.sh printed, then one
# "side.forked: <folder>" line, which the calling session copies into its
# notes.
#
# Exit codes:
#   0  — the worker started, or the list printed
#   1  — error (see stderr): F001 usage, F002 the side folder exists, F003 no
#        topic root, F004 launch-agent.sh refused or failed (its own error
#        line comes first)

set -euo pipefail

readonly ERR_USAGE="F001"
readonly ERR_EXISTS="F002"
readonly ERR_ROOT="F003"
readonly ERR_LAUNCH="F004"

readonly SIDE_PREFIX="side-"
readonly SLUG_MAX=50
readonly OUTCOME_FILE="side-outcome.txt"

usage() {
  cat <<'EOF'
Usage: fork-side-item.sh fork <claim> <<'FORK_SIDE_ITEM_PROMPT_END'
       <worker prompt>
       FORK_SIDE_ITEM_PROMPT_END
       fork-side-item.sh list
       fork-side-item.sh --help

  fork <claim>  Start a background worker in side-<slug> under the topic
                root; the worker prompt comes on standard input
  list          Print each side-* folder under the topic root with its
                state: an outcome, or open
  --help        Show this help message
EOF
}

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/issue-settings.sh"
# shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/slugify.sh"
# shellcheck disable=SC1091 # sourced sibling skill; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/topic-root.sh"

die() {
  echo "fork-side-item $1 error: $2" >&2
  exit 1
}

# resolve_root — set `root` to the topic root, or stop with F003.
resolve_root() {
  local reason=""
  root=""
  if ! _issue_context_topic_root root reason; then
    case "$reason" in
      settings)
        die "$ERR_ROOT" "the settings file $SETTINGS_FILE could not be read, so launchAgentDefaultFolder is unknown; fix the file" ;;
      relative | missing)
        die "$ERR_ROOT" "launchAgentDefaultFolder in $SETTINGS_FILE is '$SETTINGS_LAUNCH_AGENT_DEFAULT_FOLDER', which is not an absolute path to an existing directory; fix the setting" ;;
      *)
        die "$ERR_ROOT" "not inside a git repository and launchAgentDefaultFolder is not set, so there is no topic root for side folders" ;;
    esac
  fi
}

# state_of <folder> — print the state of a side folder: the first field of its
# close record, or "open".
state_of() {
  local line="" outcome
  if [ -f "$1/$OUTCOME_FILE" ] && [ -r "$1/$OUTCOME_FILE" ]; then
    IFS= read -r line < "$1/$OUTCOME_FILE" || line="${line:-}"
  fi
  outcome="${line%%$'\t'*}"
  outcome="${outcome//[[:space:]]/}"
  printf '%s' "${outcome:-open}"
}

case "${1-}" in
  --help)
    usage
    exit 0
    ;;
  list)
    [ "$#" -eq 1 ] || die "$ERR_USAGE" "list takes no other arguments"
    resolve_root
    for dir in "$root/$SIDE_PREFIX"*; do
      [ -d "$dir" ] || continue
      printf '%s\t%s\n' "$dir" "$(state_of "$dir")"
    done
    exit 0
    ;;
  fork)
    [ "$#" -eq 2 ] || die "$ERR_USAGE" "fork takes exactly one claim; pass the worker prompt on standard input"
    claim="$2"
    ;;
  "")
    usage >&2
    die "$ERR_USAGE" "a mode is required: fork or list"
    ;;
  *)
    die "$ERR_USAGE" "unknown mode '$1'; expected fork or list"
    ;;
esac

[ -n "${claim//[[:space:]]/}" ] || die "$ERR_USAGE" "the claim is empty"

# Read here, before anything else, so an empty prompt is refused before any
# folder exists.
[ ! -t 0 ] || die "$ERR_USAGE" "the worker prompt is required on standard input"
prompt="$(cat)"
[ -n "${prompt//[[:space:]]/}" ] || die "$ERR_USAGE" "the worker prompt on standard input is empty"

slug="$(_issue_context_slugify "$claim" "$SLUG_MAX")"
name="$SIDE_PREFIX$slug"

resolve_root
side_folder="$root/$name"
if [ -e "$side_folder" ]; then
  die "$ERR_EXISTS" "$side_folder exists already (state: $(state_of "$side_folder")); if it holds this item, do not fork it again; if the item differs, reword the claim"
fi

if ! launch_output="$(printf '%s\n' "$prompt" | "$_self_dir/../launch-agent/launch-agent.sh" "$name" --bg)"; then
  [ -z "$launch_output" ] || printf '%s\n' "$launch_output"
  die "$ERR_LAUNCH" "launch-agent.sh did not start the worker for $name; its error is above"
fi

printf '%s\n' "$launch_output"
folder_line="$(printf '%s\n' "$launch_output" | sed -n 's/^Folder: //p' | head -n 1)"
printf 'side.forked: %s\n' "${folder_line:-$side_folder}"
