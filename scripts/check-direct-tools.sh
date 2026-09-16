#!/usr/bin/env bash
#
# check-direct-tools.sh — Repo-local direct permission validator.
#
# Every skill must declare, in its own allowed-tools, each repo script it tells
# the reader to run. check-transitive-tools.sh audits the other half of the
# rule, skill-to-skill coverage, and never looks at a skill's own script calls,
# so a skill that gains a script call and not the matching permission passes
# every gate and then stops at a permission prompt in front of a user.
#
# Usage: check-direct-tools.sh [skills-root]
#
#   skills-root   Skills directory to audit (default: <script>/../skills)
#
# What counts as a call: a reference to skills/<skill>/<script>.sh inside a
# fenced code block. A skill shows the reader a command by fencing it, so the
# fence is the signal. A reference in ordinary prose is description, not
# instruction: /file-placement says which skills delegate their filenames to
# target-path.sh without ever running it, and a rule that could not tell those
# apart would push a permission onto a skill that has no use for one.
#
# A skill declaring Bash(*) needs nothing else: it is the one wildcard, matching
# the rule check-transitive-tools.sh applies.
#
# A declaration covers a call when it contains the call's whole
# skills/<skill>/<script>.sh path. Matching the bare filename instead would let
# a permission for one skill's target-path.sh satisfy a call to another's, and
# the skill would then pass this gate and stop at a permission prompt anyway,
# which is the failure the gate exists to catch.
#
# Output: one gap line per missing permission, exit 1 if any remain, or exit 0
# with no output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SKILLS_ROOT="$(cd "$SCRIPT_DIR/../skills" && pwd)"

SKILLS_ROOT="${1:-$DEFAULT_SKILLS_ROOT}"

if [ ! -d "$SKILLS_ROOT" ]; then
  echo "error: skills root not found: $SKILLS_ROOT" >&2
  exit 1
fi

# front_matter <file> — print the front matter block, first --- to second.
front_matter() {
  awk '/^---$/ { seen++; if (seen == 2) exit; next } seen == 1' "$1"
}

# fenced_calls <file> — print each skills/<skill>/<script>.sh referenced inside
# a fenced code block, one per line, deduplicated. Script paths carry no
# spaces, so the caller may split this on whitespace.
fenced_calls() {
  awk '
    /^[[:space:]]*```/ { infence = !infence; next }
    infence {
      while (match($0, /skills\/[a-z0-9-]+\/[a-z0-9._-]+\.sh/)) {
        print substr($0, RSTART, RLENGTH)
        $0 = substr($0, RSTART + RLENGTH)
      }
    }
  ' "$1" | sort -u
}

# allowed_tools <file> — print the front matter's allowed-tools declaration:
# the key line plus any indented continuation lines. YAML allows the value to
# wrap, check-transitive-tools.sh reads it that way, and a checker that kept
# only the key line would report a wrapped permission as a gap.
allowed_tools() {
  front_matter "$1" | awk '
    /^allowed-tools:/ { collecting = 1; print; next }
    collecting && /^[[:space:]]/ { print; next }
    collecting { exit }
  '
}

gaps=0

for skill_file in "$SKILLS_ROOT"/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill="$(basename "$(dirname "$skill_file")")"
  allowed="$(allowed_tools "$skill_file")"

  case "$allowed" in
    *"Bash(*)"*) continue ;;
  esac

  calls="$(fenced_calls "$skill_file")"
  # Unquoted on purpose: one call per line, and no script path holds a space.
  # shellcheck disable=SC2086
  for call in $calls; do
    case "$allowed" in
      *"$call"*) continue ;;
    esac
    echo "skills/$skill/SKILL.md: calls $call but does not declare it in allowed-tools"
    gaps=1
  done
done

exit "$gaps"
