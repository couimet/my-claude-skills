#!/usr/bin/env bats

load test_helper

FIXTURES="$PROJECT_ROOT/tests/fixtures"

# --- Helper: extract JSON block from scratchpad ---

extract_json() {
  sed -n '/^```json$/,/^```$/p' "$1" | sed '1d;$d'
}

# =============================================================
# start-issue plan: required sections
# =============================================================

@test "start-issue plan: has Context section" {
  grep -q "^## Context" "$FIXTURES/eval-start-issue-plan.txt"
}

@test "start-issue plan: has Assumptions Made section" {
  grep -q "^## Assumptions Made" "$FIXTURES/eval-start-issue-plan.txt"
}

@test "start-issue plan: has Implementation Plan section" {
  grep -q "^## Implementation Plan" "$FIXTURES/eval-start-issue-plan.txt"
}

@test "start-issue plan: has Files to Modify section" {
  grep -q "^## Files to Modify" "$FIXTURES/eval-start-issue-plan.txt"
}

@test "start-issue plan: has Documentation & Discoverability section" {
  grep -q "^## Documentation & Discoverability" "$FIXTURES/eval-start-issue-plan.txt"
}

@test "start-issue plan: has Acceptance Criteria section" {
  grep -q "^## Acceptance Criteria" "$FIXTURES/eval-start-issue-plan.txt"
}

@test "start-issue plan: has Base branch field" {
  grep -q "^Base branch:" "$FIXTURES/eval-start-issue-plan.txt"
}

@test "start-issue plan: JSON block is valid and has finish_issue_on_complete: true" {
  json="$(extract_json "$FIXTURES/eval-start-issue-plan.txt")"
  echo "$json" | jq -e '.finish_issue_on_complete == true' >/dev/null
}

@test "start-issue plan: all steps have status pending" {
  json="$(extract_json "$FIXTURES/eval-start-issue-plan.txt")"
  count="$(echo "$json" | jq '.steps | length')"
  [ "$count" -gt 0 ]
  non_pending="$(echo "$json" | jq '[.steps[] | select(.status != "pending")] | length')"
  [ "$non_pending" -eq 0 ]
}

@test "start-issue plan: each step has done_when field" {
  json="$(extract_json "$FIXTURES/eval-start-issue-plan.txt")"
  count="$(echo "$json" | jq '.steps | length')"
  [ "$count" -gt 0 ]
  for ((i=0; i<count; i++)); do
    echo "$json" | jq -e ".steps[$i].done_when" >/dev/null
  done
}

# =============================================================
# tackle-scratchpad-block: status transition correctness
# =============================================================

@test "tackle output: completed step has status done" {
  json="$(extract_json "$FIXTURES/eval-tackle-output.txt")"
  status="$(echo "$json" | jq -r '.steps[] | select(.id == "S001") | .status')"
  [ "$status" = "done" ]
}

@test "tackle output: active step has status in_progress" {
  json="$(extract_json "$FIXTURES/eval-tackle-output.txt")"
  status="$(echo "$json" | jq -r '.steps[] | select(.id == "S002") | .status')"
  [ "$status" = "in_progress" ]
}

@test "tackle output: future step remains pending" {
  json="$(extract_json "$FIXTURES/eval-tackle-output.txt")"
  status="$(echo "$json" | jq -r '.steps[] | select(.id == "S003") | .status')"
  [ "$status" = "pending" ]
}

@test "tackle output: in_progress step depends only on done steps" {
  json="$(extract_json "$FIXTURES/eval-tackle-output.txt")"
  # Get the in_progress step's depends_on
  deps="$(echo "$json" | jq -r '.steps[] | select(.status == "in_progress") | .depends_on[]?' 2>/dev/null)"
  for dep in $deps; do
    dep_status="$(echo "$json" | jq -r --arg id "$dep" '.steps[] | select(.id == $id) | .status')"
    [ "$dep_status" = "done" ]
  done
}

@test "tackle output: no step skips pending to done directly" {
  json="$(extract_json "$FIXTURES/eval-tackle-output.txt")"
  # Steps after the in_progress one should not be done
  in_progress_found=false
  statuses="$(echo "$json" | jq -r '.steps[].status')"
  for status in $statuses; do
    if [ "$in_progress_found" = true ] && [ "$status" = "done" ]; then
      # A step after in_progress is done — that's a skip
      return 1
    fi
    if [ "$status" = "in_progress" ]; then
      in_progress_found=true
    fi
  done
}

# =============================================================
# finish-issue PR description: required sections
# =============================================================

@test "finish-issue PR desc: has Summary section" {
  grep -q "^## Summary" "$FIXTURES/eval-finish-pr-desc.txt"
}

@test "finish-issue PR desc: has Changes section" {
  grep -q "^## Changes" "$FIXTURES/eval-finish-pr-desc.txt"
}

@test "finish-issue PR desc: has Test Plan section" {
  grep -q "^## Test Plan" "$FIXTURES/eval-finish-pr-desc.txt"
}

@test "finish-issue PR desc: has Documentation section" {
  grep -q "^## Documentation" "$FIXTURES/eval-finish-pr-desc.txt"
}

@test "finish-issue PR desc: has Related section" {
  grep -q "^## Related" "$FIXTURES/eval-finish-pr-desc.txt"
}

@test "finish-issue PR desc: has Closes link with full GitHub URL" {
  grep -Eq "^- Closes https://github\.com/[^/]+/[^/]+/issues/[0-9]+" "$FIXTURES/eval-finish-pr-desc.txt"
}

@test "finish-issue PR desc: title starts with branch name in brackets" {
  first_line="$(head -1 "$FIXTURES/eval-finish-pr-desc.txt")"
  [[ "$first_line" =~ ^\[issues/[0-9]+\] ]]
}

@test "finish-issue PR desc: does not reference .claude-work/ paths" {
  ! grep -q "\.claude-work/" "$FIXTURES/eval-finish-pr-desc.txt"
}
