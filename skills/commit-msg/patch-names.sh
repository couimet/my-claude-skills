#!/usr/bin/env bash
#
# patch-names.sh — Sourced helper. Defines patch_names, which prints the files
# of a patch for commit-scope.sh and commit-plan.sh.
#
# patch_names <patch> — print each file that a section of <patch> changes, one
# per line, relative to the repository root, deduplicated. The names come from
# the header of each `diff --git` section, so a binary section and a section
# with only a mode change give their files too:
#   - `diff --git a/<P> b/<P>`, when both sides name the same file;
#   - `rename from`, `rename to`, `copy from`, and `copy to`;
#   - `--- a/<P>` and `+++ b/<P>`, before the first hunk of the section.
# Returns 2 when a section gives no name, such as a section whose names git
# quoted (a name with a special character). The names of the other sections
# still print.

patch_names() {
  # kcov-exclude-start
  awk '
    function close_section() { if (open && !named) bad = 1 }
    /^diff --git / {
      close_section()
      open = 1; named = 0; header = 1
      s = substr($0, 12)
      n = length(s)
      if (n % 2 == 1 && n >= 7) {
        half = (n - 5) / 2
        p = substr(s, 3, half)
        if (substr(s, 1, 2) == "a/" && substr(s, 3 + half, 3) == " b/" && substr(s, 6 + half) == p) {
          print p; named = 1
        }
      }
      next
    }
    !header { next }
    /^@@/ || /^GIT binary patch/ || /^Binary files / { header = 0; next }
    /^(rename|copy) (from|to) / { p = $0; sub(/^(rename|copy) (from|to) /, "", p); print p; named = 1; next }
    /^--- a\// { print substr($0, 7); named = 1; next }
    /^\+\+\+ b\// { print substr($0, 7); named = 1; next }
    END { close_section(); exit(bad ? 2 : 0) }
  ' "$1" | sort -u
  # kcov-exclude-end
  return "${PIPESTATUS[0]}"
}
