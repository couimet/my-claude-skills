#!/usr/bin/env bash
#
# remove-issue-dir.sh — Safely remove an issue's working directory under
# the shared .claude-work/ root.
#
# This is the ONLY code path that performs rm -rf in the cleanup-issue
# workflow.  ID validation is enforced here, not in prose.
#
# The target directory is <base>/<segment>/<id> (settings key `segment`,
# default "issues"); an empty segment places it directly at <base>/<id>,
# where the structural category directories are reserved and refused.
#
# Usage: remove-issue-dir.sh <base> <id>
#
#   <base>  Absolute path to .claude-work/ (from claude-work-root.sh)
#   <id>    Issue ID validated against ^[A-Za-z0-9][A-Za-z0-9._-]*$
#
# Output (stdout):
#   Absolute path removed (e.g., /Users/x/project/.claude-work/issues/42).
#
# Exit codes:
#   0  — directory removed (or didn't exist — idempotent)
#   1  — validation error (see stderr)
#   2  — runtime error (see stderr)

set -euo pipefail

readonly ERR_BAD_ID="R001"
readonly ERR_BAD_BASE="R002"
readonly ERR_RM_FAILED="R003"

# --- Validate arguments ---
if [ $# -ne 2 ]; then
  echo "remove-issue-dir $ERR_BAD_BASE error: usage: remove-issue-dir.sh <base> <id>" >&2
  exit 1
fi

base="$1"
id="$2"

# --- Validate base ---
# Must be an absolute path ending in .claude-work (belt-and-suspenders — the
# only caller is claude-work-root.sh, but guard against accidents).
# Check existence first so a non-existent directory surfaces clearly.
if [ ! -d "$base" ]; then
  echo "remove-issue-dir $ERR_BAD_BASE error: base directory does not exist: $base" >&2
  exit 2
fi

if [[ "$base" != /* ]] || [[ "$base" != */.claude-work ]]; then
  echo "remove-issue-dir $ERR_BAD_BASE error: base must be an absolute path ending in /.claude-work, got: $base" >&2
  exit 1
fi

# --- Load settings (segment) ---
_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/issue-settings.sh"

# --- Validate ID ---
# Must start with alphanumeric (rejects . and ..) and contain only safe chars.
if ! [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "remove-issue-dir $ERR_BAD_ID error: invalid issue ID '$id'. Expected ^[A-Za-z0-9][A-Za-z0-9._-]*\$" >&2
  exit 1
fi

# In a flat layout (empty segment) the structural category directories live at
# the same level as work-item folders; they are reserved names and must never
# be removable as work items.
if [ -z "$SETTINGS_SEGMENT" ]; then
  case "$id" in
    notes|questions|scratchpads|commit-msgs)
      echo "remove-issue-dir $ERR_BAD_ID error: '$id' is a reserved directory name, not an issue ID" >&2
      exit 1
      ;;
  esac
fi

# --- Construct and verify target ---
segment_rel=""
if [ -n "$SETTINGS_SEGMENT" ]; then
  target="${base}/${SETTINGS_SEGMENT}/${id}"
  segment_rel="${SETTINGS_SEGMENT}/"
else
  target="${base}/${id}"
fi

# Resolve physical path to catch symlink-based escapes.
# If the directory doesn't exist, resolve the longest existing prefix.
target_physical="$(if cd "$target" 2>/dev/null; then pwd -P; fi)"
if [ -z "$target_physical" ]; then
  # Directory doesn't exist — resolve the parent to check it's safe.
  target_physical="$(if cd "$(dirname "$target")" 2>/dev/null; then pwd -P; fi)"
  if [ -z "$target_physical" ]; then
    # Parent doesn't exist either.  Construct what it would be.
    base_physical="$(cd "$base" 2>/dev/null && pwd -P)"
    target_physical="${base_physical}/${segment_rel}${id}"
  else
    target_physical="${target_physical}/$(basename "$target")"
  fi
fi

# Belt-and-suspenders: the resolved physical path must stay under the segment
# directory (or under <base> itself when the segment is empty).
base_physical="$(cd "$base" 2>/dev/null && pwd -P)"
if [ -n "$SETTINGS_SEGMENT" ]; then
  expected_prefix="${base_physical}/${SETTINGS_SEGMENT}/"
else
  expected_prefix="${base_physical}/"
fi

if [[ "$target_physical" != "$expected_prefix"* ]]; then
  echo "remove-issue-dir $ERR_BAD_ID error: resolved path '$target_physical' is not under '$expected_prefix'" >&2
  exit 1
fi

# --- Remove ---
if [ -d "$target" ]; then
  if ! rm -rf "$target"; then
    echo "remove-issue-dir $ERR_RM_FAILED error: failed to remove $target" >&2
    exit 2
  fi
fi

printf '%s\n' "$target"
