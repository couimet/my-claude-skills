#!/usr/bin/env bash
#
# remove-issue-dir.sh — Safely remove an issue's working directory under
# the shared .claude-work/ root.
#
# This is the ONLY code path that performs rm -rf in the cleanup-issue
# workflow.  ID validation is enforced here, not in prose.
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

# --- Validate ID ---
# Must start with alphanumeric (rejects . and ..) and contain only safe chars.
if ! [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "remove-issue-dir $ERR_BAD_ID error: invalid issue ID '$id'. Expected ^[A-Za-z0-9][A-Za-z0-9._-]*\$" >&2
  exit 1
fi

# --- Construct and verify target ---
target="${base}/issues/${id}"

# Resolve physical path to catch symlink-based escapes.
# If the directory doesn't exist, resolve the longest existing prefix.
target_physical="$(cd "$target" 2>/dev/null && pwd -P || true)"
if [ -z "$target_physical" ]; then
  # Directory doesn't exist — resolve the parent to check it's safe.
  target_physical="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P || true)"
  if [ -z "$target_physical" ]; then
    # Parent doesn't exist either.  Construct what it would be.
    base_physical="$(cd "$base" 2>/dev/null && pwd -P)"
    target_physical="${base_physical}/issues/${id}"
  else
    target_physical="${target_physical}/$(basename "$target")"
  fi
fi

# Belt-and-suspenders: the resolved physical path must start with <base>/issues/.
base_physical="$(cd "$base" 2>/dev/null && pwd -P)"
expected_prefix="${base_physical}/issues/"

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
