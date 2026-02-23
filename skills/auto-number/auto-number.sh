#!/usr/bin/env bash
#
# auto-number.sh — Returns the next available zero-padded 4-digit sequence number.
#
# Usage: auto-number.sh <directory> <mode> [glob_pattern]
#
#   directory    — Path to scan for existing numbered files
#   mode         — "prefix" (NNNN-name.ext) or "suffix" (name-NNNN.ext)
#   glob_pattern — Optional file filter (default: all files)
#
# Output: A single line containing the next NNNN (e.g., "0001", "0042")

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "auto-number error: missing directory argument" >&2
  echo "Usage: auto-number.sh <directory> <mode> [glob_pattern]" >&2
  exit 1
fi

directory="$1"
mode="${2:-prefix}"
glob_pattern="${3:-}"

if [[ "$mode" != "prefix" && "$mode" != "suffix" ]]; then
  echo "auto-number error: invalid mode '$mode' (expected prefix or suffix)" >&2
  exit 1
fi

max=0

for filepath in "$directory"/*; do
  # Skip if glob matched nothing (the literal glob string)
  [ -e "$filepath" ] || continue

  filename="$(basename "$filepath")"

  # Apply glob_pattern filter if provided
  if [ -n "$glob_pattern" ]; then
    case "$filename" in
      $glob_pattern) ;;  # matches — continue
      *) continue ;;     # doesn't match — skip
    esac
  fi

  num=""
  if [ "$mode" = "prefix" ]; then
    # Extract leading digits before first dash: NNNN-rest
    if [[ "$filename" =~ ^([0-9]+)- ]]; then
      num="${BASH_REMATCH[1]}"
    fi
  else
    # Extract trailing digits after last dash, before extension: rest-NNNN.ext
    # Strip extension first, then grab trailing digits
    name_no_ext="${filename%.*}"
    if [[ "$name_no_ext" =~ -([0-9]+)$ ]]; then
      num="${BASH_REMATCH[1]}"
    fi
  fi

  if [ -n "$num" ]; then
    # Remove leading zeros for arithmetic comparison
    num_val=$((10#$num))
    if [ "$num_val" -gt "$max" ]; then
      max="$num_val"
    fi
  fi
done

next=$((max + 1))
printf "%04d\n" "$next"
