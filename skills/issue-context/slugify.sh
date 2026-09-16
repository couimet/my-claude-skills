#!/usr/bin/env bash
#
# slugify.sh — The one definition of how free-form text becomes a slug. Source
# this file; do not execute it.
#
# The rules were target-path.sh's inline pipeline until set-work-folder.sh
# needed the same slug for a session filename. Two copies of a slug definition
# drift, and the drift is invisible: both keep producing plausible names. This
# file is the single home, and every caller that names something from user text
# goes through it.
#
# Functions defined on source:
#   _issue_context_slugify <text> [max-len]
#
# The rules produce basic ASCII by construction: lowercase, each run of
# non-alphanumeric characters becomes one hyphen, repeats collapse, and the
# ends are trimmed. An input that yields nothing usable produces "file" rather
# than an empty string, so a caller can always interpolate the result.
#
# max-len is optional and bounds the result, the "file" fallback included.
# Absent, empty, or 0 means no bound, which is what target-path.sh has always
# done and what keeps its filenames byte-identical across this extraction. A
# bounded result is trimmed again after the cut, so it never ends on the hyphen
# the cut exposed.

# _issue_context_slugify <text> [max-len] — print the slug for <text>.
# Prints "file" when <text> holds nothing sluggable. Never fails.
_issue_context_slugify() {
  local text="${1-}" max_len="${2-}" slug

  slug="$(printf '%s' "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"

  # The fallback comes first so every value this function returns leaves
  # through the same bound. Bounding first would let "file" out at four
  # characters under a smaller bound, which is the one case where the result
  # would not honour the max-len this function documents.
  if [ -z "$slug" ]; then
    slug="file"
  fi

  # A bound cannot empty what it cuts: the trim after the cut only removes
  # trailing hyphens, and a slug that is all hyphens was already trimmed to
  # nothing above, which is what the fallback has just replaced.
  if [ -n "$max_len" ] && [ "$max_len" -gt 0 ] 2>/dev/null; then
    if [ "${#slug}" -gt "$max_len" ]; then
      slug="${slug:0:$max_len}"
      slug="${slug%"${slug##*[!-]}"}"
    fi
  fi

  printf '%s' "$slug"
}
