#!/usr/bin/env bash
#
# find-obsolete-issue-dirs.sh — List work-item working directories under the
# shared .claude-work/ root whose issue is obsolete: the PR was merged into
# main and no open PR remains on its branch, or the issue is closed with no
# open PR and no local branch matching the identifier.
#
# The work-item directory root is <base>/<segment> (settings key `segment`,
# default "issues"); an empty segment places work-item folders directly under
# <base>. A folder is treated as a work item when its name is a plausible
# identifier, and a branch or PR head ref corresponds to that folder when the
# configured `branchPatterns` capture the identifier (first match wins),
# matching the single-owner branch gate in issue-context/branch-issue-id.sh.
#
# Classification is conservative: any failure to gather state keeps the
# folder. This script only reports — the caller decides what to delete.
#
# Must be run from the repo checkout: gh api resolves {owner}/{repo} from the
# CWD remote, and git branch reads the CWD repo.
#
# Usage: find-obsolete-issue-dirs.sh <base>
#
#   <base>  Absolute path to .claude-work/ (from claude-work-root.sh)
#
# Output (stdout):
#   DELETABLE<TAB><absolute path><TAB><reason>  per obsolete folder
#   Skipped: <name> (not a valid work-item identifier, not checked)
#                                                per structurally invalid folder
#
# Exit codes:
#   0  — classification completed (even when nothing is deletable)
#   1  — validation error (see stderr)
#
# Error codes:
#   F001 — wrong number of arguments
#   F002 — base is not an existing absolute path ending in /.claude-work

set -euo pipefail

readonly ERR_ARGS="F001"
readonly ERR_BAD_BASE="F002"

# --- Validate arguments ---
if [ $# -ne 1 ]; then
  echo "find-obsolete-issue-dirs $ERR_ARGS error: usage: find-obsolete-issue-dirs.sh <base>" >&2
  exit 1
fi

base="$1"

# --- Validate base ---
# Must be an existing absolute path ending in .claude-work (belt-and-suspenders
# — the only caller is claude-work-root.sh, but guard against accidents).
if [ ! -d "$base" ] || [[ "$base" != /* ]] || [[ "$base" != */.claude-work ]]; then
  echo "find-obsolete-issue-dirs $ERR_BAD_BASE error: base must be an existing absolute path ending in /.claude-work, got: $base" >&2
  exit 1
fi

# gh missing entirely: can't know anything, so treat every folder as keep.
# This guard runs before settings load or any external binary, so it fires
# cleanly even under a PATH containing only bash (the bats gh-unavailability
# test restricts PATH to bash alone).
if ! command -v gh >/dev/null 2>&1; then
  echo "find-obsolete-issue-dirs: gh not available; treating all folders as keep" >&2
  exit 0
fi

# --- Load settings (segment + branchPatterns) ---
_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/issue-settings.sh"

# Directory that holds work-item folders: <base>/<segment>, or <base> itself
# when the segment is empty. Child dirs of this root are the candidates.
if [ -n "$SETTINGS_SEGMENT" ]; then
  work_root="${base}/${SETTINGS_SEGMENT}"
else
  work_root="${base}"
fi

# is_category_dir <name> — the four structural dirs that live at the .claude-work
# root in a flat (empty segment) layout. They are never work items.
is_category_dir() {
  case "$1" in
    notes|questions|scratchpads|commit-msgs) return 0 ;;
    *) return 1 ;;
  esac
}

# is_plausible_identifier <name> — a folder name that could be a work-item
# identifier: non-empty, not a hidden entry, no whitespace.
is_plausible_identifier() {
  local name="$1"
  [ -n "$name" ] || return 1
  [[ "$name" == .* ]] && return 1
  [[ "$name" == *[[:space:]]* ]] && return 1
  return 0
}

# branch_matches_folder <branch> <name> — 0 when a configured branchPatterns
# entry matches <branch> with capture group one equal to <name>.
branch_matches_folder() {
  local branch="$1" name="$2" pattern
  for pattern in "${SETTINGS_BRANCH_PATTERNS[@]}"; do
    if [[ "$branch" =~ $pattern ]]; then
      if [ -n "${BASH_REMATCH[1]:-}" ] && [ "${BASH_REMATCH[1]}" = "$name" ]; then
        return 0
      fi
    fi
  done
  return 1
}

# --- Gather state (any failed query stops classification) ---
# Each query must succeed: a failed query must not read as an empty answer,
# or a folder could be marked DELETABLE while the state of its PR or branch
# is unknown. Empty output from a successful query is legitimate (no PRs,
# no closed issues, no local branches).
# pr_rows: TAB-separated head branch, base branch, state, PR number.
# gh pr list / gh issue list cap results at --limit, and a capped view is
# unsafe: a PR past the cap could hide an open PR and wrongly mark its
# folder DELETABLE, and a closed issue past the cap would hide a valid
# cleanup candidate. gh api --paginate instead follows every Link-header
# page until exhaustion — the inventory is complete with no cap.
if ! pr_rows="$(gh api --paginate 'repos/{owner}/{repo}/pulls?state=all&per_page=100' --jq '.[] | [.head.ref, .base.ref, (if .merged then "MERGED" elif .state == "open" then "OPEN" else "CLOSED" end), .number] | @tsv' 2>/dev/null)"; then
  echo "find-obsolete-issue-dirs: gh pulls query failed; treating all folders as keep" >&2
  exit 0
fi
# closed_issues: newline-separated closed issue numbers. The REST issues
# endpoint also returns pull requests, so exclude them via .pull_request.
if ! closed_issues="$(gh api --paginate 'repos/{owner}/{repo}/issues?state=closed&per_page=100' --jq '.[] | select(.pull_request | not) | .number' 2>/dev/null)"; then
  echo "find-obsolete-issue-dirs: gh issues query failed; treating all folders as keep" >&2
  exit 0
fi
# local_branches: newline-separated local branch names. Correspondence to a
# folder is decided per-folder through branchPatterns, so every local branch
# is gathered (not just a literal issues/* subset).
if ! local_branches="$(git branch --format='%(refname:short)' 2>/dev/null)"; then
  echo "find-obsolete-issue-dirs: git branch failed; treating all folders as keep" >&2
  exit 0
fi

# --- Classify each candidate directory under the work root, sorted ---
# Non-directory entries are ignored. DELETABLE lines print first, then the
# Skipped lines, so the caller can grep '^DELETABLE' without noise.
skipped=""
while IFS= read -r dir; do
  name="$(basename "$dir")"

  # In a flat layout the work root is the .claude-work root itself, which also
  # holds the structural category directories; never treat them as work items.
  if [ -z "$SETTINGS_SEGMENT" ] && is_category_dir "$name"; then
    continue
  fi

  # A name that cannot be a branch identifier isn't a work-item folder.
  if ! is_plausible_identifier "$name"; then
    skipped+="Skipped: ${name} (not a valid work-item identifier, not checked)"$'\n'
    continue
  fi

  # Scan PR rows for this folder's identifier. Any open PR blocks deletion;
  # otherwise a merged PR into main wins.
  merged_pr=""
  open_pr="no"
  while IFS=$'\t' read -r head base state prnum; do
    [ -z "$head" ] && continue
    if branch_matches_folder "$head" "$name"; then
      if [ "$state" = "MERGED" ] && [ "$base" = "main" ]; then
        merged_pr="$prnum"
      fi
      if [ "$state" = "OPEN" ]; then
        open_pr="yes"
      fi
    fi
  done <<< "$pr_rows"

  # Scan local branches for this folder's identifier.
  has_local_branch="no"
  while IFS= read -r branch; do
    [ -z "$branch" ] && continue
    if branch_matches_folder "$branch" "$name"; then
      has_local_branch="yes"
      break
    fi
  done <<< "$local_branches"

  if [ "$open_pr" = "yes" ]; then
    continue
  elif [ -n "$merged_pr" ]; then
    printf 'DELETABLE\t%s\tmerged PR into main (PR #%s)\n' "$dir" "$merged_pr"
  elif printf '%s\n' "$closed_issues" | grep -qx "$name" \
      && [ "$has_local_branch" = "no" ]; then
    printf 'DELETABLE\t%s\tissue closed, no open PR, no local branch\n' "$dir"
  fi
done < <(find "$work_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

printf '%s' "$skipped"

exit 0
