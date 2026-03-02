#!/usr/bin/env bash
#
# ensure-gitignore.sh — Checks that .gitignore contains the Claude skill working
# directory sentinel. Appends the sentinel block if missing.
#
# Usage: ensure-gitignore.sh [GITIGNORE_PATH]
#
# Arguments:
#   GITIGNORE_PATH  Optional path to the .gitignore file (default: .gitignore)
#
# Output (one line on stdout):
#   present  — sentinel already in file; no changes made
#   added    — sentinel was missing; block appended to file
#
# Exit codes:
#   0  — success (either present or added)
#   1  — error (see stderr for details)

set -euo pipefail

GITIGNORE="${1:-.gitignore}"
SENTINEL="# Claude skill working directories"
BLOCK=".claude-work/"

if grep -qF "$SENTINEL" "$GITIGNORE" 2>/dev/null; then
  echo "present"
  exit 0
fi

# Sentinel missing — append block with a leading blank line if file is non-empty
if [[ -f "$GITIGNORE" ]] && [[ -s "$GITIGNORE" ]]; then
  echo "" >> "$GITIGNORE"
fi

printf '%s\n%s\n' "$SENTINEL" "$BLOCK" >> "$GITIGNORE"
echo "added"
