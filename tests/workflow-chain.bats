#!/usr/bin/env bats

load test_helper

FIXTURES="$PROJECT_ROOT/tests/fixtures"

# --- Helper: extract JSON block from scratchpad ---

extract_json() {
  sed -n '/^```json$/,/^```$/p' "$1" | sed '1d;$d'
}

# --- Scratchpad JSON: valid structure ---

@test "scratchpad: JSON block is valid JSON" {
  json="$(extract_json "$FIXTURES/scratchpad-valid.txt")"
  echo "$json" | jq . >/dev/null 2>&1
  [ $? -eq 0 ]
}

@test "scratchpad: all step IDs match S[0-9]{3} pattern" {
  json="$(extract_json "$FIXTURES/scratchpad-valid.txt")"
  ids="$(echo "$json" | jq -r '.steps[].id')"
  for id in $ids; do
    [[ "$id" =~ ^S[0-9]{3}$ ]]
  done
}

@test "scratchpad: all status values are legal" {
  json="$(extract_json "$FIXTURES/scratchpad-valid.txt")"
  statuses="$(echo "$json" | jq -r '.steps[].status')"
  for status in $statuses; do
    [[ "$status" =~ ^(pending|in_progress|done|blocked)$ ]]
  done
}

@test "scratchpad: depends_on references only valid step IDs" {
  json="$(extract_json "$FIXTURES/scratchpad-valid.txt")"
  all_ids="$(echo "$json" | jq -r '.steps[].id' | tr '\n' ' ')"
  deps="$(echo "$json" | jq -r '.steps[].depends_on[]?' 2>/dev/null)"
  for dep in $deps; do
    [[ " $all_ids " == *" $dep "* ]]
  done
}

@test "scratchpad: steps array is non-empty" {
  json="$(extract_json "$FIXTURES/scratchpad-valid.txt")"
  count="$(echo "$json" | jq '.steps | length')"
  [ "$count" -gt 0 ]
}

@test "scratchpad: each step has required fields (id, title, status, depends_on, files, tasks)" {
  json="$(extract_json "$FIXTURES/scratchpad-valid.txt")"
  count="$(echo "$json" | jq '.steps | length')"
  for ((i=0; i<count; i++)); do
    echo "$json" | jq -e ".steps[$i].id" >/dev/null
    echo "$json" | jq -e ".steps[$i].title" >/dev/null
    echo "$json" | jq -e ".steps[$i].status" >/dev/null
    echo "$json" | jq -e ".steps[$i].depends_on" >/dev/null
    echo "$json" | jq -e ".steps[$i].files" >/dev/null
    echo "$json" | jq -e ".steps[$i].tasks" >/dev/null
  done
}

# --- Scratchpad JSON: invalid fixture detection ---

@test "scratchpad: invalid status value is detected" {
  json="$(extract_json "$FIXTURES/scratchpad-invalid-status.txt")"
  statuses="$(echo "$json" | jq -r '.steps[].status')"
  found_invalid=false
  for status in $statuses; do
    if ! [[ "$status" =~ ^(pending|in_progress|done|blocked)$ ]]; then
      found_invalid=true
    fi
  done
  [ "$found_invalid" = true ]
}

# --- Status transition validation ---

@test "scratchpad: pending → in_progress is a legal transition" {
  [[ "pending" =~ ^(pending)$ ]] && [[ "in_progress" =~ ^(in_progress)$ ]]
  # Transition map: pending can go to in_progress
  from="pending"; to="in_progress"
  case "${from}->${to}" in
    "pending->in_progress"|"pending->blocked"|"in_progress->done"|"in_progress->pending"|"blocked->pending") true ;;
    *) false ;;
  esac
}

@test "scratchpad: in_progress → done is a legal transition" {
  from="in_progress"; to="done"
  case "${from}->${to}" in
    "pending->in_progress"|"pending->blocked"|"in_progress->done"|"in_progress->pending"|"blocked->pending") true ;;
    *) false ;;
  esac
}

@test "scratchpad: pending → done is NOT a legal transition" {
  from="pending"; to="done"
  case "${from}->${to}" in
    "pending->in_progress"|"pending->blocked"|"in_progress->done"|"in_progress->pending"|"blocked->pending") result=legal ;;
    *) result=illegal ;;
  esac
  [ "$result" = "illegal" ]
}

@test "scratchpad: done → pending is NOT a legal transition" {
  from="done"; to="pending"
  case "${from}->${to}" in
    "pending->in_progress"|"pending->blocked"|"in_progress->done"|"in_progress->pending"|"blocked->pending") result=legal ;;
    *) result=illegal ;;
  esac
  [ "$result" = "illegal" ]
}

# --- Commit message format ---

@test "commit-msg: first line matches [type] pattern" {
  first_line="$(head -1 "$FIXTURES/commit-msg-valid.txt")"
  [[ "$first_line" =~ ^\[.+\]\ .+ ]]
}

@test "commit-msg: has Benefits section" {
  grep -q "^Benefits:" "$FIXTURES/commit-msg-valid.txt"
}

@test "commit-msg: missing [type] prefix is detected" {
  first_line="$(head -1 "$FIXTURES/commit-msg-missing-type.txt")"
  ! [[ "$first_line" =~ ^\[.+\]\ .+ ]]
}
