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

is_legal_transition() {
  case "$1->$2" in
    "pending->in_progress"|"pending->blocked"|"in_progress->done"|"in_progress->pending"|"blocked->pending") return 0 ;;
    *) return 1 ;;
  esac
}

@test "scratchpad: pending → in_progress is a legal transition" {
  is_legal_transition "pending" "in_progress"
}

@test "scratchpad: in_progress → done is a legal transition" {
  is_legal_transition "in_progress" "done"
}

@test "scratchpad: pending → done is NOT a legal transition" {
  ! is_legal_transition "pending" "done"
}

@test "scratchpad: done → pending is NOT a legal transition" {
  ! is_legal_transition "done" "pending"
}

# --- Commit message format ---

COMMIT_SUBJECT_RE='^\[[a-z][a-z0-9 _-]*\] .+'

@test "commit-msg: first line matches [type] pattern" {
  first_line="$(head -1 "$FIXTURES/commit-msg-valid.txt")"
  [[ "$first_line" =~ $COMMIT_SUBJECT_RE ]]
}

@test "commit-msg: has Benefits section" {
  grep -q "^Benefits:" "$FIXTURES/commit-msg-valid.txt"
}

@test "commit-msg: missing [type] prefix is detected" {
  first_line="$(head -1 "$FIXTURES/commit-msg-missing-type.txt")"
  ! [[ "$first_line" =~ $COMMIT_SUBJECT_RE ]]
}
