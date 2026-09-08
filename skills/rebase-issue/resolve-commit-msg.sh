#!/usr/bin/env bash
#
# resolve-commit-msg.sh — Resolve the commit message for a rebased issue
# branch by trying three sources in order: the last-finish-issue pointer,
# a PR description file in notes/, and the git log (pre-squash commits).
# The pointer and notes live in the issue's .claude-work/ folder, resolved
# through get-issue-folder-path.sh so a configured segment is honored.
#
# Usage: resolve-commit-msg.sh <target> <issue-number>
#
#   target         The git ref being rebased onto (e.g., origin/main)
#   issue-number   The issue number extracted from the branch name
#
# Output (stdout):
#   The commit message content from the first non-empty source.
#
# Exit codes:
#   0 — success (non-empty message found)
#   1 — error (see stderr for the specific error code)
#
# Error codes:
#   C001 — wrong number of arguments
#   C003 — work-item folder resolution failed
#   C004 — all sources are empty

set -euo pipefail

readonly ERR_ARGS="C001"
readonly ERR_FOLDER="C003"
readonly ERR_EMPTY="C004"

usage() {
  cat <<'EOF'
Usage: resolve-commit-msg.sh <target> <issue-number>

  target         The git ref being rebased onto (e.g., origin/main)
  issue-number   The issue number extracted from the branch name
EOF
}

# --- Argument parsing ---

if [ "$#" -ne 2 ]; then
  echo "resolve-commit-msg $ERR_ARGS error: expected 2 arguments, got $#" >&2
  usage >&2
  exit 1
fi

target="$1"
issue_number="$2"

# Basic validation: issue_number must not be empty or contain path separators
if [ -z "$issue_number" ] || [[ "$issue_number" == */* ]]; then
  echo "resolve-commit-msg $ERR_ARGS error: invalid issue number '$issue_number'" >&2
  exit 1
fi

# --- Resolve script directory and dependencies ---

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
folder_script="${script_dir}/../issue-context/get-issue-folder-path.sh"

if [ ! -x "$folder_script" ]; then
  echo "resolve-commit-msg $ERR_FOLDER error: get-issue-folder-path.sh not found or not executable at $folder_script" >&2
  exit 1
fi

# --- Resolve the issue's .claude-work/ folder ---

# The pointer and notes live in the issue's folder, resolved through
# get-issue-folder-path.sh (the same resolver finish-issue and note write to),
# so a configured segment is honored: under a non-default segment they sit at
# <root>/<segment>/<id>/ instead of hard-coded under issues/. The folder is not
# created here — the writers (finish-issue, rebase) create it.
issue_folder="$("$folder_script" --id "$issue_number")" || {
  echo "resolve-commit-msg $ERR_FOLDER error: could not resolve work-item folder for '$issue_number' (get-issue-folder-path.sh failed)" >&2
  exit 1
}

# --- Helper: check if a file exists, is readable, and has non-empty content ---

file_has_content() {
  local f="$1"
  [ -f "$f" ] && [ -r "$f" ] && [ -s "$f" ]
}

# --- Source 1: last-finish-issue pointer ---

pointer_file="${issue_folder}/last-finish-issue"

if file_has_content "$pointer_file"; then
  # The pointer contains an absolute path to the PR description.
  pr_desc_path="$(head -n1 "$pointer_file" | tr -d '\n')"
  if [ -n "$pr_desc_path" ] && file_has_content "$pr_desc_path"; then
    cat "$pr_desc_path"
    exit 0
  fi
fi

# --- Source 2: find PR description in notes/ directory ---

notes_dir="${issue_folder}/notes"

if [ -d "$notes_dir" ]; then
  newest_note="$(find "$notes_dir" -maxdepth 1 -type f -name "*finish-issue-${issue_number}*" 2>/dev/null | sort | tail -n1)"
  if [ -n "$newest_note" ] && file_has_content "$newest_note"; then
    cat "$newest_note"
    exit 0
  fi
fi

# --- Source 3: git log (pre-squash commits) ---

# Only attempt if the target is a valid ref with commits to capture.
if git rev-parse --verify "$target" >/dev/null 2>&1; then
  commit_msgs="$(git log --format=%B "${target}..HEAD" 2>/dev/null)" || true
  if [ -n "$commit_msgs" ]; then
    printf '%s\n' "$commit_msgs"
    exit 0
  fi
fi

# --- All sources exhausted ---

echo "resolve-commit-msg $ERR_EMPTY error: all commit message sources are empty — pointer '$pointer_file' missing or empty, no PR description found in '$notes_dir', and git log '${target}..HEAD' produced no output" >&2
exit 1
