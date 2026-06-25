#!/usr/bin/env bash
#
# claude-work-root.sh — Returns the absolute path to the .claude-work/
# root directory, taking git worktrees into account.
#
# In the primary checkout, .claude-work/ lives at --show-toplevel (same
# behavior as before).  In a linked worktree, .claude-work/ lives at the
# main checkout root (one level above --git-common-dir) so all worktrees
# of the same repo share a single copy.
#
# Usage: claude-work-root.sh
#
# Output (single line on stdout):
#   Absolute path to .claude-work/ (e.g., /Users/x/project/.claude-work).
#   The directory is NOT created — callers handle that.
#
# Exit codes:
#   0  — success
#   1  — error (see stderr)

set -euo pipefail

readonly ERR_NOT_GIT="C001"
readonly ERR_NO_TOLEVEL="C002"

# --- Resolve repo root (physical path, no symlinks or ..) ---
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "claude-work-root $ERR_NOT_GIT error: not in a git repository" >&2
  exit 1
}

[ -n "$repo_root" ] || {
  echo "claude-work-root $ERR_NO_TOLEVEL error: could not resolve --show-toplevel" >&2
  exit 1
}

# Canonicalise — --show-toplevel may preserve symlinks (macOS /var vs /private/var).
repo_root="$(cd "$repo_root" && pwd -P)"

# --- Resolve a git-rev-parse path to an absolute path ---
# Paths from --git-dir / --git-common-dir are relative to --show-toplevel
# when inside the repo (or absolute on newer git).  Normalise both cases.
resolve_abs() {
  local p="$1"
  if [[ "$p" == /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s/%s\n' "$repo_root" "$p"
  fi
}

# --- Detect linked worktree ---
# --git-dir and --git-common-dir may be relative to CWD (e.g. ../.git from a
# subdirectory).  Resolve both to physical paths so string comparison works.
git_dir_raw="$(git rev-parse --git-dir 2>/dev/null)"
git_common_dir_raw="$(git rev-parse --git-common-dir 2>/dev/null)"

git_dir_abs="$(cd "$(resolve_abs "$git_dir_raw")" 2>/dev/null && pwd -P || true)"
git_common_dir_abs="$(cd "$(resolve_abs "$git_common_dir_raw")" 2>/dev/null && pwd -P || true)"

if [ -z "$git_dir_abs" ] || [ -z "$git_common_dir_abs" ]; then
  # Fallback: if resolution failed, assume primary checkout.
  main_root="$repo_root"
elif [ "$git_dir_abs" != "$git_common_dir_abs" ]; then
  # Linked worktree: place .claude-work at the main checkout root.
  # git-common-dir is the shared .git directory; the main checkout is its parent.
  main_root="$(dirname "$git_common_dir_abs")"
else
  # Primary checkout: .claude-work lives alongside the working tree.
  main_root="$repo_root"
fi

printf '%s/.claude-work\n' "$main_root"
