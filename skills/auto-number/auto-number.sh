#!/usr/bin/env bash
#
# auto-number.sh — Returns the next available zero-padded sequence number.
#
# Usage: auto-number.sh <directory> [--mode prefix|suffix] [--glob PATTERN] [--width N]
#
#   directory  — Path to scan for existing numbered files (required, positional)
#   --mode     — "prefix" (NNNN-name.ext) or "suffix" (name-NNNN.ext). Default: prefix
#   --glob     — File filter pattern (e.g., "*.txt"). Default: all files
#   --width    — Output width, 1-10. Default: 4. Safety: never truncates if next value needs more digits.
#
# Output: A single line containing the next number, zero-padded to width (e.g., "0001", "000042")

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: auto-number.sh <directory> [--mode prefix|suffix] [--glob PATTERN] [--width N]

  directory  Path to scan for existing numbered files (required)
  --mode     "prefix" (NNNN-name.ext) or "suffix" (name-NNNN.ext). Default: prefix
  --glob     File filter pattern (e.g., "*.txt"). Default: all files
  --width    Output width, 1-10. Default: 4. Never truncates if next value needs more digits.
  --help     Show this help message
EOF
}

# --- Error codes (all exit 1) ---
# E0xx: generic errors
readonly ERR_MISSING_DIR="E001"
readonly ERR_UNKNOWN_FLAG="E002"
# E1xx: parameter validation
readonly ERR_INVALID_MODE="E100"
readonly ERR_INVALID_WIDTH="E101"
readonly ERR_DIR_NOT_FOUND="E102"
readonly ERR_NOT_A_DIR="E103"
readonly ERR_DIR_NOT_READABLE="E104"

# --- Defaults ---
mode="prefix"
glob_pattern=""
width=4

# --- Parse arguments ---
# First non-flag argument is the directory
directory=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      [ $# -ge 2 ] || { echo "auto-number $ERR_INVALID_MODE error: --mode requires a value" >&2; exit 1; }
      mode="$2"
      shift 2
      ;;
    --glob)
      [ $# -ge 2 ] || { echo "auto-number $ERR_UNKNOWN_FLAG error: --glob requires a value" >&2; exit 1; }
      glob_pattern="$2"
      shift 2
      ;;
    --width)
      [ $# -ge 2 ] || { echo "auto-number $ERR_INVALID_WIDTH error: --width requires a value" >&2; exit 1; }
      width="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    --*)
      echo "auto-number $ERR_UNKNOWN_FLAG error: unknown flag '$1'" >&2
      exit 1
      ;;
    *)
      if [ -z "$directory" ]; then
        directory="$1"
      else
        echo "auto-number $ERR_UNKNOWN_FLAG error: unexpected argument '$1'" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# --- Validate directory ---
if [ -z "$directory" ]; then
  echo "auto-number $ERR_MISSING_DIR error: missing directory argument" >&2
  exit 1
fi

if [ ! -e "$directory" ]; then
  echo "auto-number $ERR_DIR_NOT_FOUND error: directory does not exist: '$directory'" >&2
  exit 1
fi

if [ ! -d "$directory" ]; then
  echo "auto-number $ERR_NOT_A_DIR error: path is not a directory: '$directory'" >&2
  exit 1
fi

if [ ! -r "$directory" ]; then
  echo "auto-number $ERR_DIR_NOT_READABLE error: directory not readable: '$directory'" >&2
  exit 1
fi

# --- Validate mode ---
if [[ "$mode" != "prefix" && "$mode" != "suffix" ]]; then
  echo "auto-number $ERR_INVALID_MODE error: invalid mode '$mode' (expected prefix or suffix)" >&2
  exit 1
fi

# --- Validate width ---
if ! [[ "$width" =~ ^[0-9]+$ ]] || [ "$width" -lt 1 ] || [ "$width" -gt 10 ]; then
  echo "auto-number $ERR_INVALID_WIDTH error: --width must be an integer between 1 and 10 (got '$width')" >&2
  exit 1
fi

# --- Scan directory ---
max=0

for filepath in "$directory"/*; do
  # Skip if glob matched nothing (the literal glob string)
  [ -e "$filepath" ] || continue

  filename="$(basename "$filepath")"

  # Apply glob_pattern filter if provided
  if [ -n "$glob_pattern" ]; then
    # shellcheck disable=SC2254
    case "$filename" in
      $glob_pattern) ;;  # matches — intentionally unquoted for glob matching
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

# --- Output next number ---
next=$((max + 1))

# Safety: use at least enough digits to represent the value
digits_needed=${#next}
if [ "$digits_needed" -gt "$width" ]; then
  width="$digits_needed"
fi

printf "%0${width}d\n" "$next"
