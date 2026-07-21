#!/usr/bin/env bash
#
# resolve-target.sh — Resolve the rebase target ref and mode (normal or stacked)
# for an issue branch. The target comes from an explicit argument, gh pr list
# (authoritative for PR stacking relationships), the base-branch marker file,
# or a fallback to origin/main. Mode is classified uniformly as stacked when
# the target matches issues/*, normal otherwise.
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
#   T004 — base-branch marker ref no longer exists on remote

set -euo pipefail

readonly ERR_ARGS="T001"
readonly ERR_INVALID_ISSUE="T002"
readonly ERR_CLAUDE_ROOT="T003"
readonly ERR_STALE_MARKER="T004"

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
  # Auto-resolve from gh pr list (authoritative) or base-branch marker.
  marker_file="${claude_work_root}/issues/${issue_number}/base-branch"

  # First, try gh pr list as the authoritative source. The GitHub PR owns the
  # stacking relationship. gh may not be available (tests), so guard with command -v.
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || true
  if [ -n "$current_branch" ] && command -v gh >/dev/null 2>&1; then
    base_ref="$(gh pr list --head "$current_branch" --json baseRefName --jq '.[0].baseRefName' 2>/dev/null)" || true
    if [ -n "$base_ref" ] && [ "$base_ref" != "null" ]; then
      # Guard against double origin/ prefix.
      if [[ "$base_ref" != origin/* ]]; then
        base_ref="origin/${base_ref}"
      fi
      target="$base_ref"
      # Update the marker file so it stays current.
      mkdir -p "$(dirname "$marker_file")"
      printf '%s' "$base_ref" > "$marker_file"
    fi
  fi

  # If gh pr list didn't resolve, fall back to the marker file.
  if [ -z "$target" ]; then
    if [ -f "$marker_file" ] && [ -r "$marker_file" ] && [ -s "$marker_file" ]; then
      base_branch="$(head -n1 "$marker_file" | tr -d '\n')"

      if [ -n "$base_branch" ]; then
        # Strip origin/ prefix for the ls-remote check — ls-remote expects
        # bare branch names (e.g., "main", not "origin/main").
        check_ref="${base_branch#origin/}"
        if git ls-remote origin "refs/heads/$check_ref" 2>/dev/null | grep -q .; then
          # Base PR hasn't been merged yet — rebase onto it.
          # Use the original value so the origin/ prefix is preserved in the target.
          target="$base_branch"
        else
          # Remote ref no longer exists — the upstream branch was likely
          # merged and deleted. The marker is stale; don't guess.
          echo "resolve-target $ERR_STALE_MARKER error: base-branch marker points to '$base_branch' which no longer exists on remote. The upstream branch was likely merged and deleted. Run '/rebase-issue <new-target>' to specify the correct target, or update the marker file at '$marker_file'." >&2
          exit 1
        fi
      fi
    fi
  fi

  # Fallback if no marker exists and gh pr list returned nothing.
  if [ -z "$target" ]; then
    target="origin/main"
  fi
fi

# --- Classify mode ---

mode="normal"
bare_target="${target#origin/}"
if [[ "$bare_target" =~ ^issues/[0-9] ]]; then
  mode="stacked"
fi

# --- Output ---

printf 'TARGET=%s\n' "$target"
printf 'MODE=%s\n' "$mode"
