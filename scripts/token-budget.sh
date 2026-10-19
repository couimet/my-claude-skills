#!/usr/bin/env bash
#
# token-budget.sh — Report what each skill costs the model, and whether it is
# over its size budget.
#
# Every SKILL.md enters context when its skill is invoked, and every
# description enters context once per session whether or not the skill runs.
# Those are the two numbers this prints, so a claim about token use can be
# checked rather than asserted.
#
# The per-skill number is the whole file, front matter included, which is what
# a reader reproduces with `wc -c` and what the caps in ADR 005 were
# calibrated against. A description is therefore counted twice, once in its
# file and once in the session floor, and that is deliberate: the two totals
# price two different costs, and a description is paid in both.
#
# Caps, per ADR 005:
#   foundation (user-invocable: false)   4000 bytes
#   composite  (skill-kind: composite)  12000 bytes
#   ordinary   (everything else)         8000 bytes
#
# A skill over its cap must be listed in skills/.budget-allowlist, one
# `<skill> <bytes>` line per skill, `#` for comments. The allowlist is the
# backlog: an entry is a debt, and it shows up in a diff when someone adds
# one. The bytes are the measured size of the skill when the line was last
# written, and they are a ratchet: a listed skill over its cap may shrink, but
# it may not grow past them. Without the ratchet, a listed skill grows with no
# limit and no sign, because the allowlist covers any size. A listed skill
# under its cap passes whatever its line records, because it owes no debt.
#
# Usage:
#   token-budget.sh [--check] [--skills-dir <dir>]
#
#   --check   exit 1 when a skill is over its cap and not allowlisted, or
#             when a listed skill over its cap is larger than its recorded
#             bytes or its line records no bytes (report mode is the
#             default and always exits 0)
#
# Exit codes:
#   0  — report printed, or --check found nothing
#   1  — --check found a skill over its cap that the allowlist does not
#        cover
#   2  — usage error

set -euo pipefail

CHARS_PER_TOKEN=38 # tenths, i.e. 3.8 chars/token

usage() {
  cat <<'EOF'
Usage: token-budget.sh [--check] [--skills-dir <dir>]

  --check        Exit 1 when a skill exceeds its cap and the allowlist does
                 not cover its size
  --skills-dir   Directory holding <skill>/SKILL.md (default: skills/)
  --help         Show this help message
EOF
}

SKILLS_DIR=""
CHECK=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    # A missing value must be a usage error, not a failing `shift 2`: that
    # fails under `set -e` and exits 1, the status reserved for a real
    # over-budget finding.
    --skills-dir)
      if [ "$#" -lt 2 ]; then
        echo "token-budget B001 error: --skills-dir needs a directory" >&2
        usage >&2
        exit 2
      fi
      SKILLS_DIR="$2"; shift 2
      ;;
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

# allowance <name> — print the bytes that the allowlist records for <name>,
# the second field of its line, or "-" when the line records none. Returns 1
# when no line names <name>. The name must match the whole first field.
allowance() {
  [ -f "$ALLOWLIST" ] || return 1
  awk -v name="$1" '
    # kcov-exclude-start
    /^[[:space:]]*(#|$)/ { next }
    $1 == name { print ($2 == "" ? "-" : $2); found = 1; exit }
    END { exit !found }
  ' "$ALLOWLIST" # kcov-exclude-end
}

# Front-matter field read. Only the first --- block counts; a line further down
# the body is documentation, not configuration.
fm_field() {
  awk -v key="$2" '
    # kcov-exclude-start
    NR == 1 && $0 == "---" { infm = 1; next }
    infm && $0 == "---"    { exit }
    infm && index($0, key ":") == 1 {
      sub(/^[^:]*:[[:space:]]*/, "")
      print
      exit
    }
  ' "$1" # kcov-exclude-end
}

tokens_of() { echo $(( $1 * 10 / CHARS_PER_TOKEN )); }

total_file=0
total_desc=0
over=0
rows=""
findings=""

for dir in "$SKILLS_DIR"/*/; do
  [ -f "$dir/SKILL.md" ] || continue
  name="$(basename "$dir")"
  file="$dir/SKILL.md"
  bytes="$(wc -c < "$file" | tr -d ' ')"
  desc="$(fm_field "$file" description)"
  # Bytes, not characters: ${#desc} undercounts any non-ASCII description,
  # and the cost being measured is bytes. printf keeps the trailing newline
  # `wc -c` would otherwise add out of the count.
  desc_bytes="$(printf '%s' "$desc" | wc -c | tr -d ' ')"
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
    if ! recorded="$(allowance "$name")"; then
      status="OVER"
      findings="$findings$name is $bytes bytes, over its $cap cap and not in .budget-allowlist"$'\n'
    else
      case "$recorded" in
        '' | *[!0-9]*)
          status="NOSIZE"
          findings="$findings$name is in .budget-allowlist with no recorded size; write its line as '$name $bytes'"$'\n'
          ;;
        *)
          if [ "$bytes" -le "$recorded" ]; then
            status="ALLOWED"
          else
            status="GREW"
            findings="$findings$name is $bytes bytes, past the $recorded bytes that .budget-allowlist records"$'\n'
          fi
          ;;
      esac
    fi
    [ "$status" = "ALLOWED" ] || over=$((over + 1))
  fi

  total_file=$((total_file + bytes))
  total_desc=$((total_desc + desc_bytes))
  rows="$rows$(printf '%-26s %-11s %7s %7s %6s %5s  %s\n' \
    "$name" "$tier" "$bytes" "$(tokens_of "$bytes")" "$desc_bytes" "$cap" "$status")"$'\n'
done

if [ "$CHECK" -eq 1 ]; then
  if [ "$over" -gt 0 ]; then
    printf '%s' "$findings" >&2
    echo "token-budget: $over skill(s) over budget. Shrink them, or add or raise a line in skills/.budget-allowlist and say why in the commit." >&2
    exit 1
  fi
  exit 0
fi

printf '%-26s %-11s %7s %7s %6s %5s  %s\n' SKILL TIER BYTES TOKENS DESC CAP STATUS
printf '%s' "$rows" | sort
echo
printf 'Files:        %7s bytes  ~%s tokens (loaded per invocation, per chain)\n' \
  "$total_file" "$(tokens_of "$total_file")"
printf 'Descriptions: %7s bytes  ~%s tokens (session floor, loaded whether or not a skill runs)\n' \
  "$total_desc" "$(tokens_of "$total_desc")"
if [ "$over" -gt 0 ]; then
  printf '\n%s skill(s) over budget. Run with --check to fail on them.\n' "$over"
fi
