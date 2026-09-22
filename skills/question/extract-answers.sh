#!/usr/bin/env bash
#
# extract-answers.sh — Print the answers of a /question wave file without
# reading the file into a model's context.
#
# A wave file runs to several thousand tokens while its answers run to a few
# dozen. A script's source never enters the model's context, only its stdout,
# so the filtering this performs costs nothing.
#
# Usage: extract-answers.sh <wave-file>
#
# Output (stdout):
#   ACKNOWLEDGED: <n> of <total>
#   UNANSWERED: <space-separated answer ids still carrying [RECOMMENDED]>
#   A001: <letter> | <text of the option that letter names>
#     <further lines of a multi-line answer, indented, printed whole>
#   HELD: <n>, then one indented line per held question
#   RETIRED: <n>, then one indented line per retired question
#
# Exit codes:
#   0 — success
#   1 — error (see stderr for the specific error code)
#
# Error codes:
#   X001 — wrong number of arguments
#   X002 — file does not exist or is not readable
#   X003 — file is empty
#   X004 — an answer opener has no closer
#   X005 — a closer has no matching opener
#   X006 — a closer's id does not match the opener it closes
#   X007 — the file contains no answers

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: extract-answers.sh <wave-file>

  wave-file   Absolute path to a /question-format questions file
EOF
}

die() {
  printf 'extract-answers %s error: %s\n' "$1" "$2" >&2
  exit 1
}

if [ "$#" -ne 1 ]; then
  usage >&2
  die "X001" "expected exactly one argument, got $#"
fi

FILE="$1"

[ -r "$FILE" ] || die "X002" "cannot read '$FILE'"
[ -s "$FILE" ] || die "X003" "'$FILE' is empty"

awk '
function flush_answer(   i, letter, marked, body, key, text, line) {
  if (open_id == "") return
  marked = (opener ~ /\[RECOMMENDED\]/)
  body = opener
  sub(/\[RECOMMENDED\][[:space:]]*/, "", body)
  # The letter is the first bare A-E token left on the opener line.
  letter = ""
  if (match(body, /^[[:space:]]*[A-E]([[:space:]]|[;,.]|$)/)) {
    letter = substr(body, RSTART, RLENGTH)
    gsub(/[^A-E]/, "", letter)
  }
  total++
  if (marked) {
    unack = unack (unack == "" ? "" : " ") "A" open_id
    line = sprintf("A%s: [RECOMMENDED] %s", open_id, (letter == "" ? body : letter))
  } else {
    ack++
    line = sprintf("A%s: %s", open_id, (letter == "" ? body : letter))
  }
  key = open_id letter
  text = (letter != "" && (key in opt)) ? opt[key] : ""
  if (text != "") line = line " | " text
  nout++; out[nout] = line
  for (i = 1; i <= nbody; i++) { nout++; out[nout] = "  " bodyline[i] }
  open_id = ""; nbody = 0
}

/^## Q[0-9][0-9][0-9]:/ {
  match($0, /Q[0-9][0-9][0-9]/)
  curq = substr($0, RSTART + 1, 3)
  next
}

# Option label lines, only outside an open answer region.
open_id == "" && /^[A-E]\) / {
  letter = substr($0, 1, 1)
  text = substr($0, 4)
  p = index(text, " - ")
  if (p > 0) text = substr(text, 1, p - 1)
  if (length(text) > 120) text = substr(text, 1, 117) "..."
  opt[curq letter] = text
  next
}

/^A[0-9][0-9][0-9]:/ {
  if (open_id != "") {
    printf "extract-answers X004 error: answer A%s has no </A%s> closer\n", open_id, open_id > "/dev/stderr"
    bad = 1; exit 1
  }
  open_id = substr($0, 2, 3)
  opener = substr($0, 6)
  nbody = 0
  next
}

/^<\/A[0-9][0-9][0-9]>[[:space:]]*$/ {
  cid = substr($0, 4, 3)
  if (open_id == "") {
    printf "extract-answers X005 error: closer </A%s> has no opener\n", cid > "/dev/stderr"
    bad = 1; exit 1
  }
  if (cid != open_id) {
    printf "extract-answers X006 error: answer A%s is closed by </A%s>\n", open_id, cid > "/dev/stderr"
    bad = 1; exit 1
  }
  flush_answer()
  next
}

open_id != "" {
  if ($0 ~ /[^[:space:]]/) { nbody++; bodyline[nbody] = $0 }
  next
}

/^Held:/  { section = "held";    next }
/^Retired:/ { section = "retired"; next }

/^- / {
  # The held list is what a resume works from: it names every question still
  # waiting and the answers it waits on. A count alone cannot drive that, so
  # the text is carried through. Held lists run to a few short lines, which
  # costs nothing against the file this script exists to avoid reading.
  if (section == "held") { held++; heldline[held] = $0 }
  else if (section == "retired") { retired++; retiredline[retired] = $0 }
  next
}

END {
  if (bad) exit 1
  if (open_id != "") {
    printf "extract-answers X004 error: answer A%s has no </A%s> closer\n", open_id, open_id > "/dev/stderr"
    exit 1
  }
  if (total == 0) {
    printf "extract-answers X007 error: no answers found\n" > "/dev/stderr"
    exit 1
  }
  printf "ACKNOWLEDGED: %d of %d\n", ack, total
  if (unack != "") printf "UNANSWERED: %s\n", unack
  printf "HELD: %d\n", held
  for (i = 1; i <= held; i++) printf "  %s\n", heldline[i]
  printf "RETIRED: %d\n", retired
  for (i = 1; i <= retired; i++) printf "  %s\n", retiredline[i]
  for (i = 1; i <= nout; i++) print out[i]
}
' "$FILE"
