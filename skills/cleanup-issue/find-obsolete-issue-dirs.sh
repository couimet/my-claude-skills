#!/usr/bin/env bash
#
# find-obsolete-issue-dirs.sh — List issue working directories under the
# shared .claude-work/ root whose issue is obsolete: the PR was merged into
# main and no open PR remains on its branch, or the issue is closed with no
# open PR and no local issues/* branch.
#
# Classification is conservative: any failure to gather state keeps the
# folder. This script only reports — the caller decides what to delete.
#
# Must be run from the repo checkout: gh api resolves {owner}/{repo} from the
# CWD remote, and git branch --list reads the CWD repo.
#
# Usage: find-obsolete-issue-dirs.sh <base>
#
#   <base>  Absolute path to .claude-work/ (from claude-work-root.sh)
#
# Output (stdout):
#   DELETABLE<TAB><absolute path><TAB><reason>  per obsolete folder
#   Skipped: <name> (non-numeric ID, not checked)  per non-numeric folder
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

# --- Gather state (any failed query stops classification) ---
# gh missing entirely: can't know anything, so treat every folder as keep.
if ! command -v gh >/dev/null 2>&1; then
  echo "find-obsolete-issue-dirs: gh not available; treating all folders as keep" >&2
  exit 0
fi

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
# local_branches: newline-separated local issues/* branch names.
if ! local_branches="$(git branch --format='%(refname:short)' --list 'issues/*' 2>/dev/null)"; then
  echo "find-obsolete-issue-dirs: git branch failed; treating all folders as keep" >&2
  exit 0
fi

# --- Classify each child directory of <base>/issues/, sorted ---
# Non-directory entries are ignored. DELETABLE lines print first, then the
# Skipped lines, so the caller can grep '^DELETABLE' without noise.
skipped=""
while IFS= read -r dir; do
  name="$(basename "$dir")"

  # Non-numeric ID: not an issue folder — report and move on.
  if ! [[ "$name" =~ ^[0-9]+$ ]]; then
    skipped+="Skipped: ${name} (non-numeric ID, not checked)"$'\n'
    continue
  fi

  # Scan PR rows for this folder's branch. Any open PR blocks deletion;
  # otherwise a merged PR into main wins.
  merged_pr=""
  open_pr="no"
  while IFS=$'\t' read -r head base state prnum; do
    [ -z "$head" ] && continue
    [[ ! "$head" =~ ^issues/${name}([-_].*)?$ ]] && continue
    if [ "$state" = "MERGED" ] && [ "$base" = "main" ]; then
      merged_pr="$prnum"
    fi
    if [ "$state" = "OPEN" ]; then
      open_pr="yes"
    fi
  done <<< "$pr_rows"

  if [ "$open_pr" = "yes" ]; then
    continue
  elif [ -n "$merged_pr" ]; then
    printf 'DELETABLE\t%s\tmerged PR into main (PR #%s)\n' "$dir" "$merged_pr"
  elif printf '%s\n' "$closed_issues" | grep -qx "$name" \
      && ! grep -Eq "^issues/${name}([-_].*)?$" <<< "$local_branches"; then
    printf 'DELETABLE\t%s\tissue closed, no open PR, no local branch\n' "$dir"
  fi
done < <(find "$base/issues" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

printf '%s' "$skipped"

exit 0
