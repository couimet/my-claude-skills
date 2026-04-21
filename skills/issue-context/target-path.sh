#!/usr/bin/env bash
#
# target-path.sh — Resolve the full target path for a numbered working file,
# combining branch detection, issue-ID extraction, slug derivation, and
# auto-numbering into one deterministic call.
#
# Usage: target-path.sh --type <type> --description <text> [--ext <ext>]
#
#   --type         "scratchpads", "questions", or "commit-msgs" (required)
#   --description  Free-form text for the slug (required; will be lowercased +
#                  hyphenated)
#   --ext          File extension without the dot. Default: txt
#
# Output (single line on stdout):
#   The full path of the next numbered file for the current branch context,
#   with the directory already created.
#
#   On an `issues/<ID>` branch:
#     .claude-work/issues/<ID>/<type>/NNNN-<slug>.<ext>
#   Otherwise:
#     .claude-work/<type>/NNNN-<slug>.<ext>
#
# Exit codes:
#   0  — success
#   1  — error (see stderr)

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: target-path.sh --type <scratchpads|questions|commit-msgs> --description <text> [--ext <ext>]

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
  scratchpads|questions|commit-msgs) ;;
  "")
    echo "target-path $ERR_MISSING_ARG error: --type is required" >&2
    exit 1
    ;;
  *)
    echo "target-path $ERR_INVALID_TYPE error: invalid --type '$type_arg' (expected scratchpads, questions, or commit-msgs)" >&2
    exit 1
    ;;
esac

# --- Validate description ---
if [ -z "$description" ]; then
  echo "target-path $ERR_MISSING_ARG error: --description is required" >&2
  exit 1
fi

# --- Detect branch and extract issue ID ---
branch="$(git branch --show-current 2>/dev/null || true)"
if [ -z "$branch" ]; then
  echo "target-path $ERR_BRANCH_DETECT error: could not detect current git branch" >&2
  exit 1
fi

issue_id=""
if [[ "$branch" == issues/* ]]; then
  segment="${branch#issues/}"
  # If the prefix before the first - or _ is purely numeric, use that; otherwise use the full segment.
  if [[ "$segment" =~ ^([0-9]+)[-_] ]]; then
    issue_id="${BASH_REMATCH[1]}"
  elif [[ "$segment" =~ ^[0-9]+$ ]]; then
    issue_id="$segment"
  else
    issue_id="$segment"
  fi
fi

# --- Determine target directory ---
if [ -n "$issue_id" ]; then
  target_dir=".claude-work/issues/${issue_id}/${type_arg}"
else
  target_dir=".claude-work/${type_arg}"
fi

# --- Slugify description ---
# lowercase, replace non-alphanumeric with hyphens, collapse consecutive
# hyphens, trim leading/trailing hyphens
slug="$(printf '%s' "$description" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"

if [ -z "$slug" ]; then
  slug="file"
fi

# --- Get next sequence number via auto-number ---
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
auto_number_script="${script_dir}/../auto-number/auto-number.sh"

if [ ! -x "$auto_number_script" ]; then
  echo "target-path $ERR_MISSING_ARG error: auto-number.sh not found or not executable at $auto_number_script" >&2
  exit 1
fi

next_num="$("$auto_number_script" "$target_dir" --glob "*.${ext}" --width 4 --mkdir)"

# --- Emit full path ---
printf '%s/%s-%s.%s\n' "$target_dir" "$next_num" "$slug" "$ext"
