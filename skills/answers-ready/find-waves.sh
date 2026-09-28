#!/usr/bin/env bash
#
# find-waves.sh — List the grill sequences whose newest wave is still
# unanswered, so /answers-ready can resolve a bare invocation.
#
# Resolving "the newest questions file" is wrong whenever two grills are open
# at once, which is the normal state while a plan is refined as it is written.
# A questions directory holding two sequences returns the file that was emitted
# last, not the one the user just answered. Grouping by sequence first removes
# that failure.
#
# A sequence is the filename slug with the working-file timestamp prefix and
# the -wave-<N> suffix removed. A questions file carrying no -wave-<N> suffix
# is its own sequence.
#
# Usage: find-waves.sh [questions-directory]
#
#   questions-directory   Defaults to <work-item folder>/questions, resolved
#                         through get-issue-folder-path.sh.
#
# Output (stdout), one line per sequence whose newest wave is unanswered:
#   <sequence><TAB><absolute path><TAB><count of answers still marked>
#
# Exit codes:
#   0 — success (zero or more lines printed)
#   1 — error (see stderr for the specific error code)
#
# Error codes:
#   W001 — too many arguments
#   W002 — the questions directory does not exist
#   W003 — the work-item folder could not be resolved

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

die() {
  printf 'find-waves %s error: %s\n' "$1" "$2" >&2
  exit 1
}

if [ "$#" -gt 1 ]; then
  printf 'Usage: find-waves.sh [questions-directory]\n' >&2
  die "W001" "expected at most one argument, got $#"
fi

resolved_here=0
if [ "$#" -eq 1 ]; then
  QDIR="$1"
else
  folder="$("$SCRIPT_DIR/../issue-context/get-issue-folder-path.sh" 2>/dev/null)" \
    || die "W003" "could not resolve the work-item folder"
  QDIR="$folder/questions"
  resolved_here=1
fi

# _report_hidden — before W002, name each outranked tier's folder that holds
# questions files, one stderr line each. A session override or a worktree
# marker set over existing work hides that work from this reader, and W002
# alone says nothing about where it went. The lines carry no error code
# because they add no reason to fail: the exit is W002 either way, and files
# elsewhere never make this reader resolve somewhere else. An explicit
# directory argument means the caller chose the location, so this runs only
# for a folder resolved here.
_report_hidden() {
  local listing line tier dir winner="" count noun
  listing="$("$SCRIPT_DIR/../issue-context/tier-folders.sh" 2>/dev/null)" || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    tier="${line%%$'\t'*}"
    dir="${line#*$'\t'}"
    if [ -z "$winner" ]; then
      winner="$tier"
      continue
    fi
    [ -d "$dir/questions" ] || continue
    # A directory find cannot read fails the pipeline under pipefail, and set -e
    # would then end the script before W002 with nothing on stderr. The report
    # is a hint beside the error, so a failed scan counts what it read and the
    # error still prints.
    count="$(find "$dir/questions" -maxdepth 1 -type f -name '*.txt' ! -size 0c 2>/dev/null \
      | wc -l | tr -d ' ' || true)"
    [ "${count:-0}" -gt 0 ] || continue
    if [ "$count" -eq 1 ]; then noun="1 questions file is"; else noun="$count questions files are"; fi
    printf 'find-waves: %s under %s/questions, where the %s tier points, but the %s tier outranks it\n' \
      "$noun" "$dir" "$tier" "$winner" >&2
  done <<EOF
$listing
EOF
}

if [ ! -d "$QDIR" ]; then
  [ "$resolved_here" -eq 0 ] || _report_hidden
  die "W002" "no questions directory at '$QDIR'"
fi

# Newest wave per sequence. Filenames sort lexicographically in creation order
# (the timestamp prefix guarantees it), and the wave number is read from the
# slug rather than inferred from that order, because a resumed grill can emit
# wave 3 long after an unrelated sequence's wave 1.
declare -a seq_names=()
declare -a seq_paths=()
declare -a seq_waves=()

_index_of() {
  local needle="$1" i
  for i in "${!seq_names[@]}"; do
    if [ "${seq_names[$i]}" = "$needle" ]; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

shopt -s nullglob
for f in "$QDIR"/*.txt; do
  # An empty file is an unwritten target-path reservation, not a wave.
  [ -s "$f" ] || continue

  base="$(basename "$f" .txt)"
  # Strip the YYYYMMDD-HHMMSS-NNN- working-file prefix when present.
  slug="${base}"
  if [[ "$base" =~ ^[0-9]{8}-[0-9]{6}-[0-9]{3}-(.*)$ ]]; then
    slug="${BASH_REMATCH[1]}"
  fi

  wave=0
  name="$slug"
  if [[ "$slug" =~ ^(.*)-wave-([0-9]+)$ ]]; then
    name="${BASH_REMATCH[1]}"
    wave="${BASH_REMATCH[2]}"
  fi

  if idx="$(_index_of "$name")"; then
    if [ "$wave" -gt "${seq_waves[$idx]}" ]; then
      seq_paths[idx]="$f"
      seq_waves[idx]="$wave"
    fi
  else
    seq_names+=("$name")
    seq_paths+=("$f")
    seq_waves+=("$wave")
  fi
done
shopt -u nullglob

for i in "${!seq_names[@]}"; do
  path="${seq_paths[$i]}"
  # Count the marker only where it opens an answer. The token also appears in
  # prose whenever a wave file discusses the convention, and counting those
  # reported a phantom unanswered question on a fully answered file, forever.
  # Same reasoning as the closer rule in /question-format: a line that quotes a
  # delimiter while discussing it is content, not a delimiter.
  marked="$(grep -cE '^A[0-9]{3}: *\[RECOMMENDED\]' "$path" || true)"
  [ "$marked" -gt 0 ] || continue
  printf '%s\t%s\t%s\n' "${seq_names[$i]}" "$path" "$marked"
done
