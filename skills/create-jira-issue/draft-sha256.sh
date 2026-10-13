#!/usr/bin/env bash
#
# draft-sha256.sh — Print the SHA-256 of a draft's filed text: its title and body.
#
# The ticket-writing plugin reviews a draft and prints `SHA256: <hex>` for the
# approved text. /create-jira-issue compares that value with this script's
# output, so a draft edited after its review is not filed. Both sides must hash
# the same span, so this script follows the plugin's draft_hash rule:
#
#   1. Turn "\r\n" and a lone "\r" into "\n", as Python text mode does.
#   2. Skip the front-matter block. Blank lines may come before the opening
#      `---` line. The block ends at the next `---` line. Each block line is
#      blank or matches FRONT_MATTER_LINE below. A block with any other line
#      is not front matter, and the span is then the whole file.
#   3. Remove leading lines that hold only spaces and tabs.
#   4. Hash the rest byte for byte, with any final newline.
#
# Usage: draft-sha256.sh <path>
#
# Output (one line on stdout): the lowercase hex digest.
#
# Exit codes:
#   0  — success
#   1  — error (see stderr)

set -euo pipefail

# Byte semantics: string lengths and offsets below count bytes, not characters.
export LC_ALL=C

usage() {
  cat <<'EOF'
Usage: draft-sha256.sh <path>

Prints the SHA-256 of the draft's title and body, without the front matter.

  --help  Show this help message
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

readonly ERR_ARGS="D001"
readonly ERR_READ="D002"
readonly ERR_NO_TOOL="D003"

if [ "$#" -ne 1 ]; then
  echo "draft-sha256 $ERR_ARGS error: expected exactly one path, got $#" >&2
  usage >&2
  exit 1
fi

path="$1"

if [ ! -f "$path" ] || [ ! -r "$path" ]; then
  echo "draft-sha256 $ERR_READ error: cannot read '$path'" >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
  hash_cmd=(shasum -a 256)
elif command -v sha256sum >/dev/null 2>&1; then
  hash_cmd=(sha256sum)
else
  echo "draft-sha256 $ERR_NO_TOOL error: neither shasum nor sha256sum is installed" >&2
  exit 1
fi

# The plugin's FRONT_MATTER_LINE: a YAML key, an indented line, a list item,
# or a YAML comment.
readonly FRONT_MATTER_LINE='^([A-Za-z0-9_-]+[[:space:]]*:|[[:space:]]+[^[:space:]]|[[:space:]]*-[[:space:]]|#)'
readonly BLANK_LINE='^[[:space:]]*$'
readonly FENCE_LINE='^---[[:space:]]*$'

# The trailing "x" keeps the final newlines that command substitution drops.
content="$(cat "$path"; printf x)"
content="${content%x}"
content="${content//$'\r\n'/$'\n'}"
content="${content//$'\r'/$'\n'}"

# Split on "\n" like Python's str.split: a final newline gives a last empty line.
lines=()
s="$content"
while :; do
  case "$s" in
    *$'\n'*)
      lines+=("${s%%$'\n'*}")
      s="${s#*$'\n'}"
      ;;
    *)
      lines+=("$s")
      break
      ;;
  esac
done
count="${#lines[@]}"

# position: the index of the first line after the front matter, or 0 when the
# file has none.
position=0
open=0
while [ "$open" -lt "$count" ] && [[ "${lines[$open]}" =~ $BLANK_LINE ]]; do
  open=$((open + 1))
done
if [ "$open" -lt "$count" ] && [[ "${lines[$open]}" =~ $FENCE_LINE ]]; then
  end=$((open + 1))
  while [ "$end" -lt "$count" ] && ! [[ "${lines[$end]}" =~ $FENCE_LINE ]]; do
    end=$((end + 1))
  done
  if [ "$end" -lt "$count" ]; then
    valid=1
    i=$((open + 1))
    while [ "$i" -lt "$end" ]; do
      if ! [[ "${lines[$i]}" =~ $BLANK_LINE ]] && ! [[ "${lines[$i]}" =~ $FRONT_MATTER_LINE ]]; then
        valid=0
        break
      fi
      i=$((i + 1))
    done
    if [ "$valid" -eq 1 ]; then
      position=$((end + 1))
    fi
  fi
fi

# rest: the text after the front matter, taken by byte offset so that every
# byte after the block stays as it is.
if [ "$position" -eq 0 ]; then
  rest="$content"
elif [ "$position" -ge "$count" ]; then
  rest=""
else
  offset=0
  i=0
  while [ "$i" -lt "$position" ]; do
    offset=$((offset + ${#lines[$i]} + 1))
    i=$((i + 1))
  done
  rest="${content:$offset}"
fi

# Remove leading lines of only spaces and tabs. A last line without a newline
# stays, as in the plugin's \A(?:[ \t]*\n)+ pattern.
while [[ "$rest" == *$'\n'* ]]; do
  first="${rest%%$'\n'*}"
  case "$first" in
    *[!$' \t']*) break ;;
  esac
  rest="${rest#*$'\n'}"
done

digest="$(printf '%s' "$rest" | "${hash_cmd[@]}")"
printf '%s\n' "${digest%% *}"
