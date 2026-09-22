#!/usr/bin/env bash
#
# token-budget.sh — Report what each skill costs the model, and whether it is
# over its size budget.
#
# Every SKILL.md body enters context when its skill is invoked, and every
# description enters context once per session whether or not the skill runs.
# Those are the two numbers this prints, so a claim about token use can be
# checked rather than asserted.
#
# Caps, per ADR 005:
#   foundation (user-invocable: false)   4000 bytes
#   composite  (skill-kind: composite)  12000 bytes
#   ordinary   (everything else)         8000 bytes
#
# A skill over its cap must be listed in skills/.budget-allowlist, one name per
# line, `#` for comments. The allowlist is the backlog: an entry is a debt, and
# it shows up in a diff when someone adds one.
#
# Usage:
#   token-budget.sh [--check] [--skills-dir <dir>]
#
#   --check   exit 1 when a skill is over its cap and not allowlisted
#             (report mode is the default and always exits 0)
#
# Exit codes:
#   0  — report printed, or --check found nothing
#   1  — --check found an un-allowlisted skill over its cap
#   2  — usage error

set -euo pipefail

CHARS_PER_TOKEN=38 # tenths, i.e. 3.8 chars/token

usage() {
  cat <<'EOF'
Usage: token-budget.sh [--check] [--skills-dir <dir>]

  --check        Exit 1 when a skill exceeds its cap and is not allowlisted
  --skills-dir   Directory holding <skill>/SKILL.md (default: skills/)
  --help         Show this help message
EOF
}

SKILLS_DIR=""
CHECK=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --skills-dir) SKILLS_DIR="${2:-}"; shift 2 ;;
    --help | -h) usage; exit 0 ;;
    *) echo "token-budget B001 error: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$SKILLS_DIR" ]; then
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  SKILLS_DIR="$root/skills"
fi
if [ ! -d "$SKILLS_DIR" ]; then
  echo "token-budget B002 error: '$SKILLS_DIR' is not a directory" >&2
  exit 2
fi

ALLOWLIST="$SKILLS_DIR/.budget-allowlist"

allowlisted() {
  [ -f "$ALLOWLIST" ] || return 1
  grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST" | grep -qxF "$1"
}

# Front-matter field read. Only the first --- block counts; a line further down
# the body is documentation, not configuration.
fm_field() {
  awk -v key="$2" '
    NR == 1 && $0 == "---" { infm = 1; next }
    infm && $0 == "---"    { exit }
    infm && index($0, key ":") == 1 {
      sub(/^[^:]*:[[:space:]]*/, "")
      print
      exit
    }
  ' "$1"
}

tokens_of() { echo $(( $1 * 10 / CHARS_PER_TOKEN )); }

total_body=0
total_desc=0
over=0
rows=""

for dir in "$SKILLS_DIR"/*/; do
  [ -f "$dir/SKILL.md" ] || continue
  name="$(basename "$dir")"
  file="$dir/SKILL.md"
  bytes="$(wc -c < "$file" | tr -d ' ')"
  desc="$(fm_field "$file" description)"
  desc_bytes=${#desc}
  invocable="$(fm_field "$file" user-invocable)"
  kind="$(fm_field "$file" skill-kind)"

  if [ "$invocable" = "false" ]; then
    tier="foundation"; cap=4000
  elif [ "$kind" = "composite" ]; then
    tier="composite"; cap=12000
  else
    tier="ordinary"; cap=8000
  fi

  status="ok"
  if [ "$bytes" -gt "$cap" ]; then
    if allowlisted "$name"; then
      status="ALLOWED"
    else
      status="OVER"
      over=$((over + 1))
    fi
  fi

  total_body=$((total_body + bytes))
  total_desc=$((total_desc + desc_bytes))
  rows="$rows$(printf '%-26s %-11s %7s %7s %6s %5s  %s\n' \
    "$name" "$tier" "$bytes" "$(tokens_of "$bytes")" "$desc_bytes" "$cap" "$status")"$'\n'
done

if [ "$CHECK" -eq 1 ]; then
  if [ "$over" -gt 0 ]; then
    printf '%s' "$rows" | awk '$NF == "OVER" { printf "%s is %s bytes, over its %s cap and not in .budget-allowlist\n", $1, $3, $6 }' >&2
    echo "token-budget: $over skill(s) over budget. Shrink them, or add a line to skills/.budget-allowlist and say why in the commit." >&2
    exit 1
  fi
  exit 0
fi

printf '%-26s %-11s %7s %7s %6s %5s  %s\n' SKILL TIER BYTES TOKENS DESC CAP STATUS
printf '%s' "$rows" | sort
echo
printf 'Bodies:       %7s bytes  ~%s tokens (loaded per invocation, per chain)\n' \
  "$total_body" "$(tokens_of "$total_body")"
printf 'Descriptions: %7s bytes  ~%s tokens (session floor, loaded whether or not a skill runs)\n' \
  "$total_desc" "$(tokens_of "$total_desc")"
if [ "$over" -gt 0 ]; then
  printf '\n%s skill(s) over cap and not allowlisted. Run with --check to fail on them.\n' "$over"
fi
