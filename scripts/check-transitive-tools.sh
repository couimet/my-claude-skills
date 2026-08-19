#!/usr/bin/env bash
#
# check-transitive-tools.sh — Repo-local transitive permission validator.
#
# Every composite skill must declare the allowed-tools of every skill it
# invokes during its own flow; otherwise a valid nested workflow stops at an
# unexpected permission prompt. This script compares each caller's declared
# allowed-tools with the full allowed-tools of each skill it invokes and
# reports the missing permissions.
#
# Two modes:
#
#   check-transitive-tools.sh [skills-root]
#       Base mode: audit every (caller, invoked) pair in the invocation
#       manifest below. skills-root defaults to the skills/ directory next
#       to this script.
#
#   check-transitive-tools.sh --diff [range] [repo-root]
#       Diff mode: audit only skills/*/SKILL.md changed in <range> (default
#       origin/main..HEAD) for newly introduced /skill invocations. All git
#       commands run as `git -C <repo-root>`. repo-root defaults to the git
#       repository containing this script.
#
# Output: base mode prints one gap line per missing permission and exits 1
# if any gaps remain, or exits 0 with no output. Diff mode prints the same
# gap lines, or a single clean line, and exits 1 if any gaps remain.

set -euo pipefail

# ---------------------------------------------------------------------------
# Invocation manifest
# ---------------------------------------------------------------------------
# INVOKES maps each composite skill to the space-separated list of skills it
# invokes during its own execution flow, including conditional calls.
#
# Curation rule: only direct in-flow invocations count. Prose mentions of
# other skills and user-facing "next step" instructions (e.g. a skill telling
# the user to run a different command later) are NOT invocations and stay out
# of the manifest.
#
# pre-write is deliberately absent: its "stop and use /question" line is
# advisory guidance for the consulting skill, not an invocation performed by
# pre-write itself. Including it would force /question's script permissions
# onto every content skill that consults pre-write.
#
# The manifest is stored as "caller=invoked invoked ..." entries: macOS's
# system bash (3.2) predates associative arrays, so manifest_value() and
# manifest_callers() provide the associative lookup.
INVOKES=(
  "start-issue=note scratchpad question cleanup-issue"
  "start-side-quest=note scratchpad question"
  "finish-issue=note question"
  "tackle-pr-comment=note scratchpad question commit-msg"
  "tackle-scratchpad-block=question commit-msg finish-issue"
  "create-github-issue=note label-discovery"
  "scratchpad=question"
  "label-discovery=question"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SKILLS_ROOT="$(cd "$SCRIPT_DIR/../skills" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: check-transitive-tools.sh [skills-root]
       check-transitive-tools.sh --diff [range] [repo-root]

Base mode audits every (caller, invoked) pair in the embedded invocation
manifest. Diff mode audits only skills/*/SKILL.md changed in <range>
(default origin/main..HEAD) for newly introduced /skill invocations.

  skills-root   Skills directory to audit (default: <script>/../skills)
  range         Git diff range (default: origin/main..HEAD)
  repo-root     Git repository root (default: the repo containing this script)

Exit status: 0 = no gaps (base mode prints nothing; diff mode prints one
clean line), 1 = at least one gap was reported.
EOF
}

# manifest_callers — prints each caller key from INVOKES, one per line.
manifest_callers() {
  local entry
  for entry in "${INVOKES[@]}"; do
    printf '%s\n' "${entry%%=*}"
  done
}

# manifest_value <caller> — prints the invoked-skill list for <caller>.
manifest_value() {
  local caller="$1" entry
  for entry in "${INVOKES[@]}"; do
    if [[ "$entry" == "$caller="* ]]; then
      printf '%s\n' "${entry#*=}"
      return 0
    fi
  done
  return 1
}

# extract_tools <skill-file>
# Prints one allowed tool per line from the file's front matter
# allowed-tools: field: the text after the key on the key line plus any
# continuation lines (lines starting with whitespace) until the next front
# matter key or the closing "---". Split on commas, trimmed, empties dropped.
# An empty or absent allowed-tools means no tools.
extract_tools() {
  local file="$1"
  awk '
    /^---$/ { seen++; next }
    seen == 1 && /^allowed-tools:/ {
      sub(/^allowed-tools:[[:space:]]*/, "")
      print
      collecting = 1
      next
    }
    seen == 1 && collecting && /^[[:space:]]/ { print; next }
    seen == 1 && collecting { collecting = 0 }
  ' "$file" \
    | paste -sd ' ' - \
    | tr ',' '\n' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | sed '/^$/d'
}

# caller_has <caller-tools> <tool>
# Returns 0 if <tool> is declared by the caller (exact string match), or if
# the caller declares Bash(*) and <tool> is a Bash(...) permission (the sole
# wildcard: Bash(*) satisfies every Bash(...) entry of the invoked skill).
# Plain tools like Read, Write, Glob, Grep, Edit, AskUserQuestion match
# exactly.
caller_has() {
  local caller_tools="$1" tool="$2"
  if grep -qxF "$tool" <<<"$caller_tools"; then
    return 0
  fi
  if [[ "$tool" == "Bash("* ]] && grep -qxF 'Bash(*)' <<<"$caller_tools"; then
    return 0
  fi
  return 1
}

# report_missing <skills-root> <caller> <invoked>
# Prints one gap line per permission the invoked skill declares that the
# caller lacks. Returns 1 if any were printed.
report_missing() {
  local skills_root="$1" caller="$2" invoked="$3"
  local caller_tools invoked_tools tool gaps=0

  caller_tools="$(extract_tools "$skills_root/$caller/SKILL.md")"
  invoked_tools="$(extract_tools "$skills_root/$invoked/SKILL.md")"

  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    if ! caller_has "$caller_tools" "$tool"; then
      echo "skills/$caller/SKILL.md -> /$invoked: missing $tool"
      gaps=1
    fi
  done <<<"$invoked_tools"

  [[ "$gaps" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Base mode
# ---------------------------------------------------------------------------

base_mode() {
  local skills_root="$1"
  local caller invoked ok=1 gaps=0

  # Sanity: every manifest name (caller and invoked) must have a SKILL.md.
  # shellcheck disable=SC2086 # intentional splitting of the caller list
  for caller in $(manifest_callers | sort); do
    # shellcheck disable=SC2086 # intentional splitting of the invoked list
    for invoked in "$caller" $(manifest_value "$caller"); do
      if [[ ! -f "$skills_root/$invoked/SKILL.md" ]]; then
        echo "error: $skills_root/$invoked/SKILL.md missing (referenced in the invocation manifest)" >&2
        ok=0
      fi
    done
  done
  if [[ "$ok" -ne 1 ]]; then
    exit 1
  fi

  # shellcheck disable=SC2086 # intentional splitting of the caller list
  for caller in $(manifest_callers | sort); do
    # shellcheck disable=SC2086 # intentional splitting of the invoked list
    for invoked in $(manifest_value "$caller"); do
      if ! report_missing "$skills_root" "$caller" "$invoked"; then
        gaps=1
      fi
    done
  done

  [[ "$gaps" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Diff mode
# ---------------------------------------------------------------------------

# invoked_references <repo-root> <range> <file> <skills-root>
# Prints one skill name per line for every reference to an existing skill
# directory found in the added lines of <file>, but only when the line is an
# invocation context: a use/using/invoke/invokes/call/calls/run/runs/follow/
# via/create/creates/through/with verb (case-insensitive) immediately
# followed by optional spaces and the /skill token.
invoked_references() {
  local repo_root="$1" range="$2" file="$3" skills_root="$4"
  local line offset tok next
  local verbs="use|using|invoke|invokes|call|calls|run|runs|follow|via|create|creates|through|with"
  local re="($verbs)[[:space:]]+/([a-z][a-z-]+)"

  # Added lines only: start with "+", but not the "+++" hunk header.
  git -C "$repo_root" diff "$range" -- "$file" \
    | grep '^+' \
    | grep -v '^+++' \
    | sed 's/^+//' \
    | while IFS= read -r line; do
        while IFS=: read -r offset tok; do
          [[ -n "$tok" ]] || continue
          # Skip path components: a token immediately followed by a "/" is
          # part of a path like /skills/issue-context/, not a /skill
          # reference.
          next="${line:$((offset + ${#tok})):1}"
          if [[ "$next" == "/" ]]; then
            continue
          fi
          if [[ -d "$skills_root/$tok" ]] && grep -qiE "$re" <<<"$line"; then
            printf '%s\n' "$tok"
          fi
        done < <(grep -boE '[a-z][a-z-]+' <<<"$line")
      done \
    || true
}

diff_mode() {
  local range="$1" repo_root="$2"
  local skills_root="$repo_root/skills"
  local changed file caller invoked gaps=0

  changed="$(git -C "$repo_root" diff --name-only "$range" -- 'skills/*/SKILL.md' || true)"

  if [[ -z "$changed" ]]; then
    echo "Transitive permissions: no new gaps in changed skills."
    return 0
  fi

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    caller="${file#skills/}"
    caller="${caller%/SKILL.md}"
    if [[ ! -d "$skills_root/$caller" ]]; then
      continue
    fi
    # shellcheck disable=SC2086 # intentional splitting of the invoked list
    for invoked in $(invoked_references "$repo_root" "$range" "$file" "$skills_root"); do
      if ! report_missing "$skills_root" "$caller" "$invoked"; then
        gaps=1
      fi
    done
  done <<<"$changed"

  if [[ "$gaps" -eq 0 ]]; then
    echo "Transitive permissions: no new gaps in changed skills."
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

# repo_root_of <dir> — prints the git work tree root containing <dir>, or
# <dir> itself when <dir> is not inside a git work tree.
repo_root_of() {
  local dir="$1" root
  if root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$root"
  else
    printf '%s\n' "$dir"
  fi
}

main() {
  local mode_arg="${1:-}"

  if [[ "$mode_arg" == "--diff" ]]; then
    local range="${2:-origin/main..HEAD}"
    local repo_root="${3:-$(repo_root_of "$SCRIPT_DIR")}"
    diff_mode "$range" "$repo_root"
  elif [[ "$mode_arg" == "--help" || "$mode_arg" == "-h" ]]; then
    usage
  elif [[ "$mode_arg" == -* ]]; then
    echo "Unknown flag: $mode_arg" >&2
    usage >&2
    exit 1
  else
    base_mode "${1:-$DEFAULT_SKILLS_ROOT}"
  fi
}

main "$@"
