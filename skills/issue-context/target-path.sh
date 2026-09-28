#!/usr/bin/env bash
#
# target-path.sh — Resolve the full target path for a timestamped working file,
# combining branch detection, issue-ID extraction, slug derivation, and
# timestamp stamping into one deterministic call.
#
# Usage: target-path.sh --type <type> --description <text> [--ext <ext>]
#
#   --type         "scratchpads", "questions", "commit-msgs", or "notes" (required)
#   --description  Free-form text for the slug (required; will be lowercased +
#                  hyphenated)
#   --ext          File extension without the dot. Alphanumeric only (e.g.
#                  txt, md, json). Default: txt
#
# Output (single line on stdout):
#   The full path of the next working file for the current branch context,
#   with the directory already created. The work-item folder is resolved
#   through get-issue-folder-path.sh, so it follows the configured segment.
#
#   On a branch matching a configured branchPatterns entry (a work branch):
#     .claude-work[/<segment>]/<identifier>/<type>/YYYYMMDD-HHMMSS-NNN-<slug>.<ext>
#   Otherwise:
#     .claude-work/<type>/YYYYMMDD-HHMMSS-NNN-<slug>.<ext>
#
#   NNN orders the files created within one second, so a byte-order sort of the
#   directory is creation order. The path is reserved as an empty file before
#   it is printed, so two concurrent calls never receive the same path; the
#   caller writes over its own reservation.
#
#   A reservation whose caller never writes is swept. Before it claims a path,
#   the script removes every empty, stamped file more than ten minutes old from
#   the four type directories under the resolved folder, and names each removal
#   on stderr. Without this, an abandoned path stays forever and a "newest file
#   matching X" reader selects it and reads it empty.
#
#   The script also ensures the repository's .gitignore carries the
#   .claude-work/ sentinel, so a caller never has to make that call itself.
#   The check is best-effort and never blocks path resolution. It runs only
#   when the resolved folder sits under a .claude-work directory: a session
#   override or a worktree marker may name any folder, and the sentinel
#   protects nothing there.
#
# Exit codes:
#   0  — success
#   1  — error (see stderr)

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: target-path.sh --type <scratchpads|questions|commit-msgs|notes> --description <text> [--ext <ext>]

  --type         File category (required)
  --description  Free-form text for the slug (required)
  --ext          File extension without the dot. Default: txt
  --help         Show this help message
EOF
}

# --- Error codes ---
readonly ERR_MISSING_ARG="T001"
readonly ERR_UNKNOWN_FLAG="T002"
readonly ERR_INVALID_TYPE="T100"
readonly ERR_BRANCH_DETECT="T101"
readonly ERR_INVALID_EXT="T102"
readonly ERR_ORDINAL_EXHAUSTED="T103"

# --- Defaults ---
type_arg=""
description=""
ext="txt"

# --- Parse arguments ---
while [ $# -gt 0 ]; do
  case "$1" in
    --type)
      [ $# -ge 2 ] || { echo "target-path $ERR_MISSING_ARG error: --type requires a value" >&2; exit 1; }
      type_arg="$2"
      shift 2
      ;;
    --description)
      [ $# -ge 2 ] || { echo "target-path $ERR_MISSING_ARG error: --description requires a value" >&2; exit 1; }
      description="$2"
      shift 2
      ;;
    --ext)
      [ $# -ge 2 ] || { echo "target-path $ERR_MISSING_ARG error: --ext requires a value" >&2; exit 1; }
      ext="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "target-path $ERR_UNKNOWN_FLAG error: unexpected argument '$1'" >&2
      exit 1
      ;;
  esac
done

# --- Validate type ---
case "$type_arg" in
  scratchpads|questions|commit-msgs|notes) ;;
  "")
    echo "target-path $ERR_MISSING_ARG error: --type is required" >&2
    exit 1
    ;;
  *)
    echo "target-path $ERR_INVALID_TYPE error: invalid --type '$type_arg' (expected scratchpads, questions, commit-msgs, or notes)" >&2
    exit 1
    ;;
esac

# --- Validate description ---
if [ -z "$description" ]; then
  echo "target-path $ERR_MISSING_ARG error: --description is required" >&2
  exit 1
fi

# --- Validate ext ---
# Whitelist only bare alphanumeric extensions (txt, md, json, yaml, etc.).
# Reject dots, slashes, whitespace, glob characters, and shell metacharacters
# so the value can't be used to escape the target directory or to smuggle a
# pattern into the emitted filename.
if ! [[ "$ext" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "target-path $ERR_INVALID_EXT error: invalid --ext '$ext' (expected alphanumeric characters only)" >&2
  exit 1
fi

# --- Resolve script directory early (needed for sibling scripts) ---
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$script_dir/slugify.sh"

# --- Resolve the work-item folder (branch detection delegated to the gate) ---
# get-issue-folder-path.sh infers the identifier from the current branch and
# prints <claude-work-root>[/<segment>]/<identifier>, or just the root on a
# branch matching no branchPatterns entry (flat placement). It errors only
# when the .claude-work root cannot be resolved, which was the branch the
# old claude-work-root.sh call guarded.
folder_root="$("${script_dir}/get-issue-folder-path.sh")" || {
  echo "target-path $ERR_BRANCH_DETECT error: claude-work-root.sh failed" >&2
  exit 1
}

# --- Sweep abandoned reservations ---
# A path is claimed as an empty file before it is printed, and nothing releases
# a claim whose caller never writes. A caller that resolves a path and then
# abandons it leaves that file for good, and a "newest file matching X" reader
# then picks it and reads it empty, which is a wrong answer rather than a messy
# directory. The sweep runs before this call claims anything, so it can never
# remove the path this call is about to return.
#
# Deleting a reservation whose caller has not written yet is harmless. The
# ordinal scan below and the name it claims both carry this second's stamp, so
# two calls can only collide inside one second; a caller that writes minutes
# later recreates the file under a name no later call can claim.
#
# find applies the age and the size tests, which keeps stat and date out of
# this. Their BSD and GNU dialects disagree and need two code paths each; the
# -mmin and -size 0c predicates behave the same on both.
#
# A deliberately empty working file is swept too. Property 2 of the contract in
# /issue-context defines an empty file at a stamped path as a reservation and
# not a working file, so this follows the contract rather than bending it.
readonly SWEEP_AGE_MINUTES=10
readonly STAMPED_NAME_GLOB='20[0-9][0-9][0-1][0-9][0-3][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9]-*'

# Every type directory under the folder, not only this call's type: a stray in
# a directory that never receives another call of its own type would otherwise
# stay forever, which is exactly how the reported pair survived.
for sweep_dir in "${folder_root}/scratchpads" "${folder_root}/questions" \
  "${folder_root}/commit-msgs" "${folder_root}/notes"; do
  [ -d "$sweep_dir" ] || continue
  while IFS= read -r -d '' stale; do
    # An `if` rather than `&&`: a delete this call cannot make is not this
    # call's problem, and errexit must not turn it into a failed resolution.
    if rm -f -- "$stale" 2>/dev/null; then
      echo "target-path: swept abandoned reservation $stale" >&2
    fi
  done < <(find "$sweep_dir" -maxdepth 1 -type f -size 0c \
    -mmin +"$SWEEP_AGE_MINUTES" -name "$STAMPED_NAME_GLOB" -print0 2>/dev/null)
done

# --- Determine target directory ---
target_dir="${folder_root}/${type_arg}"

# --- Slugify description ---
# The rules live in slugify.sh so set-work-folder.sh names a session file the
# same way this names a working file. No bound is passed: these filenames have
# always been unbounded and the extraction does not change them.
slug="$(_issue_context_slugify "$description")"

# --- Ensure .claude-work/ is gitignored ---
# Done here so no caller can forget it. Every caller that writes a working file
# goes through this script, and a caller that skips the check writes an
# untracked-but-unignored file in a repository whose sentinel is missing.
# Best-effort: a failure must never stop a path from being resolved, and the
# helper's stdout must never reach ours, which is exactly one line and is a
# path.
#
# Measured at about 23ms on a call that costs roughly 170ms. Guarding it with
# an inline grep was tried and reverted: the `git rev-parse` such a guard needs
# costs as much as the spawn it avoids, so the guard added code and no speed.
#
# The target is passed rather than defaulted. ensure-gitignore.sh resolves
# `git rev-parse --show-toplevel`, which in a linked worktree is that worktree's
# root, while the working files go to the main checkout that owns the shared
# .claude-work/ directory. Without the argument the worktree gains a sentinel it
# does not need and the checkout writing the files keeps generating unignored
# ones. Trimming the folder at its .claude-work component recovers the owning
# checkout with no second process, which is the cost the note above rules out.
#
# A folder with no .claude-work component gets no call at all. The session and
# worktree tiers name a folder anywhere. A trim of such a folder removes
# nothing, and the helper then writes a .gitignore into the work folder itself,
# one for each topic folder.
# The component is matched exactly, with the trailing slash appended first, so
# a directory such as .claude-work-old is not mistaken for it. The first match
# wins because the outermost .claude-work is the one a repository owns.
gitignore_probe="${folder_root}/"
gitignore_owner="${gitignore_probe%%/.claude-work/*}"
if [ "$gitignore_owner" != "$gitignore_probe" ]; then
  "$script_dir/../ensure-gitignore/ensure-gitignore.sh" \
    "${gitignore_owner}/.gitignore" >/dev/null 2>&1 || true
fi

# --- Create the target directory ---
mkdir -p "$target_dir"

# --- Stamp the filename ---
# Local time, deliberately. `date -u` would name tomorrow's date for anything
# created after 17:00 in a UTC-7 zone, which is one of the defects this
# replaces, and /breadcrumb already stamps local time.
stamp="$(date +%Y%m%d-%H%M%S)"

# The stamp alone orders only across distinct seconds: two files created in the
# same second sort by slug, so the one created first can sort last. An ordinal
# between the stamp and the slug restores a total order. It is unconditional
# rather than added only on collision, because a digit sorts before a letter,
# so an optional ordinal would put the second file of a second ahead of the
# first and invert the order it exists to fix.
#
# Anchoring the scan to this second's literal prefix is what keeps it safe. The
# retired auto-number.sh read the leading digit run of every sibling, so one
# date-named file poisoned a whole directory. A name that does not carry this
# second's stamp and a three-digit field is never read here.
ordinal=0
for existing in "${target_dir}/${stamp}-"[0-9][0-9][0-9]-*; do
  [ -e "$existing" ] || continue
  field="${existing##*/}"
  field="${field#"${stamp}-"}"
  field="${field%%-*}"
  [[ "$field" =~ ^[0-9]{3}$ ]] || continue
  # 10# forces base 10: 008 and 009 are not valid octal.
  field=$((10#$field))
  if [ "$field" -gt "$ordinal" ]; then
    ordinal="$field"
  fi
done

# Reserve the name, do not merely test it. Two calls can both find the same
# path absent before either writes, and the later write would then replace the
# earlier file. Under noclobber the redirection opens with O_CREAT|O_EXCL, so
# the exit status reports whether this call created the path or lost the race,
# and the test and the claim are one syscall with no window between them. It
# also refuses a dangling symlink, which a plain -e test does not see and which
# would otherwise send the caller's write wherever the link points.
while :; do
  ordinal=$((ordinal + 1))
  if [ "$ordinal" -gt 999 ]; then
    echo "target-path $ERR_ORDINAL_EXHAUSTED error: ordinals for $stamp are exhausted in '$target_dir' (999 files in one second)" >&2
    exit 1
  fi
  printf -v seq '%03d' "$ordinal"
  candidate="${target_dir}/${stamp}-${seq}-${slug}.${ext}"
  if ( set -o noclobber; : > "$candidate" ) 2>/dev/null; then
    break
  fi
done

# --- Emit full path ---
printf '%s\n' "$candidate"
