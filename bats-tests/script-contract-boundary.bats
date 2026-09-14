#!/usr/bin/env bats
#
# Enforces the skill-versus-script prose boundary from docs/ADR/004.
#
# A skill that calls target-path.sh states the properties it relies on and
# never the filename format. The format is the script's business, so a
# consumer restating it is a copy that has to be maintained by whoever
# changes the script, and issues/261 is the evidence: swapping NNNN- for a
# timestamp touched a dozen prose sites that had no say in the decision, and
# the sweep still missed two.
#
# The format has exactly two homes: target-path.sh itself, and the one
# example in the /issue-context contract that is explicitly marked
# illustrative. skills/README.md is human-facing orientation rather than
# per-invocation context and is deliberately out of scope.

load test_helper

# Every skill whose body loads as context and which calls, or documents
# calling, target-path.sh.
#
# /breadcrumb is deliberately absent: it does not call target-path.sh, and it
# stamps the entries inside breadcrumb.md itself, so timestamps are genuinely
# its own concern. /issue-context is absent because it is the contract, one of
# the format's two permitted homes.
CONSUMERS="note scratchpad question commit-msg file-placement create-github-issue create-jira-issue draft-issue g2q release-article start-issue tackle-pr-comment start-side-quest finish-issue issue-draft-reader scratchpad-ref-format tackle-scratchpad-block"

@test "boundary: no consumer skill body restates the filename format" {
  local offenders=""
  for name in $CONSUMERS; do
    local skill="$PROJECT_ROOT/skills/$name/SKILL.md"
    [ -f "$skill" ] || continue
    if grep -q "YYYYMMDD-HHMMSS" "$skill"; then
      offenders="$offenders $name"
    fi
  done
  [ -z "$offenders" ] || {
    echo "These skills restate the filename format, which target-path.sh owns:$offenders"
    echo "State the property you rely on and cross-reference /issue-context instead."
    return 1
  }
}

# The format leaks through vocabulary as well as through the pattern itself.
# A description that promises "timestamped filenames" is a promise about the
# current scheme, so changing the scheme means editing every skill that made
# it. Say what the caller can rely on instead: the file is new, and it is
# uniquely named.
@test "boundary: no consumer skill names the naming scheme" {
  local offenders=""
  for name in $CONSUMERS; do
    local skill="$PROJECT_ROOT/skills/$name/SKILL.md"
    [ -f "$skill" ] || continue
    if grep -qiE "timestamp|auto-number|sequence number|numbered filename" "$skill"; then
      offenders="$offenders $name"
    fi
  done
  [ -z "$offenders" ] || {
    echo "These skills name the naming scheme rather than the property:$offenders"
    echo "Say \"a new file\" or \"uniquely named\", never how the name is built."
    return 1
  }
}

# A worked example carrying a real stamp is the format restated in another
# form, and it rots the same way. Placeholders like <plan-file>.txt teach the
# same syntax without pinning the scheme.
@test "boundary: no consumer skill embeds a concrete generated filename" {
  local offenders=""
  for name in $CONSUMERS; do
    local skill="$PROJECT_ROOT/skills/$name/SKILL.md"
    [ -f "$skill" ] || continue
    if grep -qE "20[0-9]{6}-[0-9]{6}" "$skill"; then
      offenders="$offenders $name"
    fi
  done
  [ -z "$offenders" ] || {
    echo "These skills embed a generated filename in an example:$offenders"
    echo "Use a placeholder such as <plan-file>.txt instead."
    return 1
  }
}

@test "boundary: no consumer skill body derives a timestamp itself" {
  local offenders=""
  for name in $CONSUMERS; do
    local skill="$PROJECT_ROOT/skills/$name/SKILL.md"
    [ -f "$skill" ] || continue
    # /breadcrumb legitimately stamps its own entries; it is not in the list
    # because it writes one file per issue rather than a target-path.sh file.
    if grep -q 'date +%Y%m%d' "$skill"; then
      offenders="$offenders $name"
    fi
  done
  [ -z "$offenders" ] || {
    echo "These skills derive a working-file timestamp themselves:$offenders"
    return 1
  }
}

# ============================================================================
# The format's two permitted homes still carry it, so a future cleanup that
# deletes the format everywhere fails here instead of silently leaving the
# contract undiscoverable.
# ============================================================================

@test "boundary: target-path.sh documents the format it owns" {
  grep -q "YYYYMMDD-HHMMSS" "$PROJECT_ROOT/skills/issue-context/target-path.sh"
}

@test "boundary: the contract doc states all four caller-facing properties" {
  local contract="$PROJECT_ROOT/skills/issue-context/SKILL.md"
  grep -qi "absolute" "$contract"
  grep -qi "directory exists" "$contract"
  grep -qi "unique" "$contract"
  grep -qi "lexicographic order equals creation order" "$contract"
}

@test "boundary: the contract doc marks its filename example as an example" {
  grep -qi "an example, not a specification" "$PROJECT_ROOT/skills/issue-context/SKILL.md"
}

# A shared doc that names its callers rots silently, because whoever changes a
# caller has no reason to look in the contract. Both instances found on
# 2026-09-10 had been wrong for a while: the description listed three callers
# after a fourth had joined, and the History section cited /auto-number as a
# live exemplar after that skill was deleted.
#
# Scoped to this one file on purpose. The rule does not generalize by grep,
# because direction is invisible to it: `/prose-style` in a body reads the same
# whether the doc calls prose-style or is called by it, and only the second is
# rot. Telling them apart would need a per-skill allowlist, which is the same
# kind of cross-skill detail this rule exists to delete.
@test "boundary: the contract doc names no other skill" {
  local contract="$PROJECT_ROOT/skills/issue-context/SKILL.md"
  local offenders="" name
  while read -r name; do
    # Self-references are the script paths (~/.claude/skills/issue-context/...).
    [ "$name" = "issue-context" ] && continue
    [ -d "$PROJECT_ROOT/skills/$name" ] || continue
    offenders="$offenders $name"
  done < <(grep -oE '/[a-z][a-z0-9-]+' "$contract" | sed 's|^/||' | sort -u)
  [ -z "$offenders" ] || {
    echo "The script contract names these skills:$offenders"
    echo "Describe the caller by role instead. The contract does not know who calls it."
    return 1
  }
}
