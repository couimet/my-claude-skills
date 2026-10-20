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
#   HELD: <n>, then one indented line per held question
#   RETIRED: <n>, then one indented line per retired question
#   A001: <letter> | <text of the option that letter names>
#   A002: <letter>, <letter> | <option text> ; <option text>
#     <the rest of the answer line after the letters, indented>
#     <further lines of a multi-line answer, indented, printed whole>
#
# The letters are a run of bare A-E tokens at the start of the answer line,
# split by commas, spaces, or both. The rest of the line loses one leading `;`,
# or one `.` that a space or the line end follows, and the spaces after it. It
# prints on its own line, so no text is lost.
# An answer line with no letter prints whole on the answer line.
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
#   X007 — the file contains no answers and no retired entries
#   X008 — two or more letters are followed by text that does not start with
#          `;`, so the text can be a further choice or a reason
#
# A terminal wave holds only retired entries and no answers. It is valid: it
# reports ACKNOWLEDGED: 0 of 0 with RETIRED above zero, which marks the grill
# as complete.

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
# kcov-exclude-start
function flush_answer(   i, n, l, letters, marked, body, rest, text, line) {
  if (open_id == "") return
  marked = (opener ~ /\[RECOMMENDED\]/)
  body = opener
  sub(/\[RECOMMENDED\][[:space:]]*/, "", body)
  # The letters are a run of bare A-E tokens at the start of the opener line,
  # split by commas, spaces, or both. A `.` or a `;` ends the run.
  n = 0; letters = ""; rest = body
  sub(/^[[:space:]]+/, "", rest)
  while (match(rest, /^[A-E]([[:space:]]|[;,.]|$)/)) {
    n++; l[n] = substr(rest, 1, 1)
    letters = letters (n > 1 ? ", " : "") l[n]
    rest = substr(rest, 2)
    match(rest, /^[[:space:],]*/)
    rest = substr(rest, RLENGTH + 1)
  }
  # Two or more letters followed by text can be a further choice or the start
  # of a reason. Only a `;` tells them apart, so anything else stops here.
  if (n > 1 && rest ~ /[^[:space:];,.]/ && rest !~ /^;/) {
    printf "extract-answers X008 error: answer A%s names several letters and then text with no \";\"; end the letters with \";\", as in \"A%s: %s; <reason>\"\n", open_id, open_id, letters > "/dev/stderr"
    bad = 1; exit 1
  }
  # Remove one separator only, so a reason such as `.env is required` keeps its
  # leading `.`.
  sub(/^(;|\.([[:space:]]|$))[[:space:]]*/, "", rest)
  total++
  if (marked) {
    unack = unack (unack == "" ? "" : " ") "A" open_id
    line = sprintf("A%s: [RECOMMENDED] %s", open_id, (n == 0 ? body : letters))
  } else {
    ack++
    line = sprintf("A%s: %s", open_id, (n == 0 ? body : letters))
  }
  # The option texts print only when every letter names one, so a text never
  # sits beside the wrong letter.
  text = ""
  for (i = 1; i <= n; i++) {
    if (!((open_id l[i]) in opt)) { text = ""; break }
    text = text (i > 1 ? " ; " : "") opt[open_id l[i]]
  }
  if (text != "") line = line " | " text
  nout++; out[nout] = line
  if (n > 0 && rest != "") { nout++; out[nout] = "  " rest }
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
  if (total == 0 && retired == 0) {
    printf "extract-answers X007 error: no answers and no retired entries found\n" > "/dev/stderr"
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
# kcov-exclude-end
' "$FILE"
