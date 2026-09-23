#!/usr/bin/env bash
#
# check-prose.sh — Report the mechanical prose violations in a generated file.
#
# The prose rules in /prose-style split into two kinds. The mechanical ones are
# exactly detectable from the text, and this script owns them. The judgment
# ones (AI-writing tells, filler, whether a hedge survived a conciseness pass)
# are not, and a reader still has to make those.
#
# The point is token cost, not convenience. Re-reading a generated file to
# check it by eye pulls the whole file back into context; this prints a handful
# of line numbers instead. A script's source never enters context, only its
# stdout. That is the same trade extract-answers.sh already makes.
#
# Usage: check-prose.sh <file>
#
# Output (stdout, one finding per line):
#   <line>: <CODE> <message>
#
# Codes:
#   P001  mid-paragraph line break (hard wrap)
#   P002  backtick-wrapped code reference
#   P003  plain-text line reference ("lines 26-37", "Line 539")
#   P004  short-form GitHub reference (#NNN, PR #NNN, issue #NNN)
#   P005  relative .claude-work/ path
#
# Exit codes:
#   0  — no findings
#   1  — findings printed to stdout
#   2  — usage or read error (stderr)

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check-prose.sh <file>

Reports mechanical prose violations by line number. Prints nothing and exits 0
when the file is clean. Exits 1 when it finds something, 2 on a usage error.

  --help  Show this help message
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "$#" -ne 1 ]; then
  echo "check-prose P000 error: expected exactly one file path, got $#" >&2
  usage >&2
  exit 2
fi

FILE="$1"
if [ ! -f "$FILE" ]; then
  echo "check-prose P000 error: '$FILE' is not a readable file" >&2
  exit 2
fi

findings=0
report() {
  printf '%s: %s %s\n' "$1" "$2" "$3"
  findings=1
}

# Fenced code blocks, tables and list items are exempt from every rule here.
# A fence toggles on any line whose first non-space characters are three
# backticks, so an indented fence inside a list still closes correctly.
# Markdown allows a fence up to three leading spaces and treats a fourth as
# indented content, so the line is trimmed of at most three before the marker
# is tested.
in_fence=0
lineno=0
prev_text=""
prev_no=0

while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))

  unindented="$line"
  for _ in 1 2 3; do unindented="${unindented# }"; done
  case "$unindented" in
    '```'*) in_fence=$((1 - in_fence)); prev_text=""; continue ;;
  esac
  [ "$in_fence" -eq 1 ] && continue

  # Structural lines are never prose: headings, table rows, list items,
  # blockquotes, thematic breaks, and the answer-region delimiters
  # /question-format defines. A list marker carries its trailing space, so a
  # bold label such as **Related:** stays prose and is still checked, which is
  # the form P004 misses most. A bare --- stays excluded: a front-matter
  # delimiter and a thematic break end no sentence, and reading either as prose
  # reports the line below it as a wrap.
  case "$line" in
    '#'* | '|'* | '- '* | '* '* | '---'* | '>'* | '</A'* | [0-9]'.'* | '    '*)
      prev_text=""
      continue
      ;;
  esac

  if [ -z "$line" ]; then
    prev_text=""
    continue
  fi

  # --- P001: mid-paragraph line break -------------------------------------
  # A paragraph is one continuous line. Two consecutive non-blank prose lines
  # therefore mean the first was wrapped. Only flag when the previous line
  # does not end a sentence, so a deliberate two-sentence block is not a
  # finding and the common failure (a wrap mid-sentence) still is.
  if [ -n "$prev_text" ] \
    && ! printf '%s' "$prev_text" | grep -qE '[].:;?!)"'"'"'`]$'; then
    report "$prev_no" "P001" "mid-paragraph line break (hard wrap)"
  fi

  # --- P002: backtick-wrapped code reference ------------------------------
  # Backticks become part of the parsed path and break navigation.
  # shellcheck disable=SC2016 # the backticks are the literal being matched
  if printf '%s' "$line" | grep -qE '`[A-Za-z0-9_./-]+\.[A-Za-z0-9]+#L[0-9]+[^`]*`'; then
    report "$lineno" "P002" "backtick-wrapped code reference"
  fi

  # --- P003: plain-text line reference ------------------------------------
  if printf '%s' "$line" | grep -qiE '\b(lines?[[:space:]]+[0-9]+([[:space:]]*[-to]+[[:space:]]*[0-9]+)?)\b'; then
    report "$lineno" "P003" "plain-text line reference; use path#L42 instead"
  fi

  # --- P004: short-form GitHub reference ----------------------------------
  # A bare #NNN, optionally prefixed by PR or issue. Skip a markdown heading
  # (already excluded above) and an anchor inside a URL.
  if printf '%s' "$line" | grep -qE '(^|[^A-Za-z0-9_/#])((PR|pr|issue|Issue)[[:space:]]+)?#[0-9]+\b'; then
    report "$lineno" "P004" "short-form GitHub reference; use the full URL"
  fi

  # --- P005: relative .claude-work/ path ----------------------------------
  if printf '%s' "$line" | grep -qE '(^|[^/A-Za-z0-9_.])\.claude-work/'; then
    report "$lineno" "P005" "relative .claude-work/ path; report it absolute"
  fi

  prev_text="$line"
  prev_no="$lineno"
done < "$FILE"

# A trailing wrapped line has no successor to trigger the P001 check above,
# and a paragraph that ends without terminal punctuation is not a wrap.
exit "$findings"
