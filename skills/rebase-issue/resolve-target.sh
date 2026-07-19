#!/usr/bin/env bash
#
# resolve-target.sh — Resolve the rebase target ref and mode (normal or stacked)
# for an issue branch. The target comes from an explicit argument, the
# base-branch marker file, or a fallback to origin/main. Mode is classified
# uniformly as stacked when the target matches issues/*, normal otherwise.
#
# Usage: resolve-target.sh <issue-number> [explicit-target]
#
#   issue-number     The issue number extracted from the branch name
#   explicit-target  Optional git ref (e.g., origin/main, issues/200, main)
#
# Output (stdout):
#   TARGET=<ref>
#   MODE=<stacked|normal>
#
# Exit codes:
#   0 — success
#   1 — error (see stderr for the specific error code)
#
# Error codes:
#   T001 — wrong number of arguments
#   T002 — invalid issue number
#   T003 — claude-work-root.sh failed

set -euo pipefail

readonly ERR_ARGS="T001"
readonly ERR_INVALID_ISSUE="T002"
readonly ERR_CLAUDE_ROOT="T003"

usage() {
  cat <<'EOF'
Usage: resolve-target.sh <issue-number> [explicit-target]

  issue-number     The issue number extracted from the branch name
  explicit-target  Optional git ref (e.g., origin/main, issues/200)
EOF
}

# --- Argument parsing ---

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "resolve-target $ERR_ARGS error: expected 1-2 arguments, got $#" >&2
  usage >&2
  exit 1
fi

issue_number="$1"
explicit_target="${2:-}"

# Basic validation: issue_number must not be empty or contain path separators
if [ -z "$issue_number" ] || [[ "$issue_number" == */* ]]; then
  echo "resolve-target $ERR_INVALID_ISSUE error: invalid issue number '$issue_number'" >&2
  exit 1
fi

# --- Resolve script directory and dependencies ---

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
claude_work_root_script="${script_dir}/../issue-context/claude-work-root.sh"

if [ ! -x "$claude_work_root_script" ]; then
  echo "resolve-target $ERR_CLAUDE_ROOT error: claude-work-root.sh not found or not executable at $claude_work_root_script" >&2
  exit 1
fi

# --- Resolve the .claude-work/ root ---

claude_work_root="$("$claude_work_root_script")" || {
  echo "resolve-target $ERR_CLAUDE_ROOT error: claude-work-root.sh failed" >&2
  exit 1
}

# --- Resolve target ---

target=""

if [ -n "$explicit_target" ]; then
  # Explicit argument always wins.
  target="$explicit_target"
else
  # Auto-resolve from base-branch marker.
  marker_file="${claude_work_root}/issues/${issue_number}/base-branch"

  if [ -f "$marker_file" ] && [ -r "$marker_file" ] && [ -s "$marker_file" ]; then
    base_branch="$(head -n1 "$marker_file" | tr -d '\n')"

    if [ -n "$base_branch" ]; then
      # Verify the recorded base branch still exists remotely.
      if git ls-remote origin "$base_branch" 2>/dev/null | grep -q .; then
        # Base PR hasn't been merged yet — rebase onto it.
        target="$base_branch"
      fi
    fi
  fi

  # Fallback if marker was missing, empty, or the remote ref is gone.
  if [ -z "$target" ]; then
    target="origin/main"
  fi
fi

# --- Classify mode ---

mode="normal"
if [[ "$target" =~ ^issues/[0-9] ]]; then
  mode="stacked"
fi

# --- Output ---

printf 'TARGET=%s\n' "$target"
printf 'MODE=%s\n' "$mode"
