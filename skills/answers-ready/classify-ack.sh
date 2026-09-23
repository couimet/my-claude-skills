#!/usr/bin/env bash
#
# classify-ack.sh — Say what kind of acknowledgment file a path names, and for
# a working document, whether its decisions are still unacknowledged.
#
# Two different files carry an acknowledgment. A questions wave file carries
# `ANNN:` answers, read by extract-answers.sh. A /tackle-pr-comment working
# document carries `Decision:` lines instead, and the extractor cannot read it:
# it reports "no answers found", which describes an empty wave file rather than
# the wrong kind of file. This routes the caller to the right reader.
#
# Usage: classify-ack.sh <file>
#
# Output (stdout):
#   KIND: wave                 the file holds ANNN: answers; use extract-answers.sh
#   KIND: document             the file holds Decision: lines
#   DECISIONS: <n>             (document only) total decisions
#   UNACKNOWLEDGED: <n>        (document only) decisions still carrying the marker
#   <item> - <verdict>         (document only) one line per still-marked decision
#
# A marker counts only where it opens a decision, `^Decision:`. The token also
# appears in prose wherever the convention is discussed, and counting those
# reports a decision nobody left unread.
#
# Exit codes:
#   0  — classified (see KIND)
#   1  — the file is neither shape
#   2  — usage or read error

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: classify-ack.sh <file>

Prints KIND: wave or KIND: document, and for a document the decision counts
and every decision still carrying [RECOMMENDED].

  --help  Show this help message
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "$#" -ne 1 ]; then
  echo "classify-ack C001 error: expected exactly one file path, got $#" >&2
  usage >&2
  exit 2
fi

FILE="$1"
if [ ! -f "$FILE" ]; then
  echo "classify-ack C002 error: '$FILE' is not a readable file" >&2
  exit 2
fi

if grep -qE '^A[0-9]{3}:' "$FILE"; then
  echo "KIND: wave"
  exit 0
fi

if ! grep -qE '^Decision:' "$FILE"; then
  echo "classify-ack C003 error: '$FILE' holds neither ANNN: answers nor Decision: lines, so it is not an acknowledgment file" >&2
  exit 1
fi

echo "KIND: document"

total="$(grep -cE '^Decision:' "$FILE" || true)"
marked="$(grep -cE '^Decision:.*\[RECOMMENDED\]' "$FILE" || true)"
echo "DECISIONS: $total"
echo "UNACKNOWLEDGED: $marked"

# Name each still-marked decision by the feedback item that heads it, so the
# caller can tell the user which ones to look at without reading the file.
if [ "$marked" -gt 0 ]; then
  awk '
    # kcov-exclude-start
    /^###[[:space:]]+Feedback[[:space:]]/ {
      item = $0
      sub(/^###[[:space:]]+/, "", item)
      sub(/:.*$/, "", item)
      next
    }
    /^Decision:.*\[RECOMMENDED\]/ {
      verdict = $0
      sub(/^Decision:[[:space:]]*\[RECOMMENDED\][[:space:]]*/, "", verdict)
      printf "%s - %s\n", (item == "" ? "(unnamed decision)" : item), verdict
    }
    # kcov-exclude-end
  ' "$FILE"
fi
