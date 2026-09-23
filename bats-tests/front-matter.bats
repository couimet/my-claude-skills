#!/usr/bin/env bats
#
# Front-matter shape. Every scalar field a tool reads must be a string.
#
# A value that starts with `[` or `{` and is not quoted is a YAML flow
# collection, so `argument-hint: [optional: issue-number-or-url]` parses as a
# list holding a map rather than as the hint text. Nothing in the suite caught
# it, and an editor validating the schema is the only thing that did.

bats_require_minimum_version 1.7.0

load test_helper

# Fields whose value a tool reads as a string. user-invocable is excluded: it
# is a boolean and YAML should parse it as one.
SCALAR_FIELDS='name|version|description|argument-hint|allowed-tools|skill-kind'

@test "front-matter: no scalar field parses as a YAML flow collection" {
  local offenders=""
  for f in "$PROJECT_ROOT"/skills/*/SKILL.md; do
    # Front matter only: the first --- block.
    local bad
    bad="$(awk -v fields="$SCALAR_FIELDS" '
      NR == 1 && $0 == "---" { infm = 1; next }
      infm && $0 == "---"    { exit }
      infm && $0 ~ "^(" fields "):[[:space:]]*[[{]" { print NR ": " $0 }
    ' "$f")"
    if [ -n "$bad" ]; then
      offenders="$offenders
${f#"$PROJECT_ROOT"/}
$bad"
    fi
  done
  if [ -n "$offenders" ]; then
    echo "Unquoted [ or { starts a YAML flow collection, so these are not strings:$offenders"
    echo "Quote the value, e.g. argument-hint: '[issue-number-or-url]'"
    return 1
  fi
}

@test "front-matter: every skill has a name that matches its directory" {
  local offenders="" dir name declared
  for f in "$PROJECT_ROOT"/skills/*/SKILL.md; do
    dir="$(basename "$(dirname "$f")")"
    declared="$(awk '
      NR == 1 && $0 == "---" { infm = 1; next }
      infm && $0 == "---"    { exit }
      infm && /^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); print; exit }
    ' "$f")"
    [ "$dir" = "$declared" ] || offenders="$offenders $dir(declared:$declared)"
  done
  [ -z "$offenders" ] || {
    echo "name: must match the directory:$offenders"
    return 1
  }
}

@test "front-matter: skill-kind is composite when present" {
  local offenders="" kind
  for f in "$PROJECT_ROOT"/skills/*/SKILL.md; do
    kind="$(awk '
      NR == 1 && $0 == "---" { infm = 1; next }
      infm && $0 == "---"    { exit }
      infm && /^skill-kind:[[:space:]]*/ { sub(/^skill-kind:[[:space:]]*/, ""); print; exit }
    ' "$f")"
    [ -z "$kind" ] || [ "$kind" = "composite" ] \
      || offenders="$offenders $(basename "$(dirname "$f")")=$kind"
  done
  [ -z "$offenders" ] || {
    echo "skill-kind accepts only 'composite':$offenders"
    return 1
  }
}
