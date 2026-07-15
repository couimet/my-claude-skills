#!/usr/bin/env bash
#
# link-dependency.sh — Link a GitHub issue dependency using addBlockedBy mutation.
#
# Usage: link-dependency.sh --subject-owner OWNER --subject-repo REPO --subject-number NUMBER \
#                           --target-owner OWNER --target-repo REPO --target-number NUMBER \
#                           --relationship blocked-by|is-blocking
#
#   --subject-owner   Owner of the subject issue (the issue being created or on the current branch)
#   --subject-repo    Repository of the subject issue
#   --subject-number  Subject issue number
#   --target-owner    Owner of the target issue (the dependency)
#   --target-repo     Repository of the target issue
#   --target-number   Target issue number
#   --relationship    "blocked-by" (subject is blocked by target) or
#                     "is-blocking" (subject is blocking target)
#
# Uses addBlockedBy mutation with globally-unique node IDs, so cross-repo linking
# works the same as same-repo. Uses jq -n to build GraphQL payloads via temp files,
# avoiding zsh history expansion that silently strips ! from type annotations.
#
# Output: "blocked #<subject> ← #<target>" or "blocking #<subject> → #<target>" on success.
# Error messages on failure (exit 1).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: link-dependency.sh --subject-owner OWNER --subject-repo REPO --subject-number NUMBER \
                          --target-owner OWNER --target-repo REPO --target-number NUMBER \
                          --relationship blocked-by|is-blocking

  --subject-owner   Owner of the subject issue
  --subject-repo    Repository of the subject issue
  --subject-number  Subject issue number
  --target-owner    Owner of the target issue (the dependency)
  --target-repo     Repository of the target issue
  --target-number   Target issue number
  --relationship    "blocked-by" (subject is blocked by target) or
                    "is-blocking" (subject is blocking target)
  --help            Show this help message
EOF
}

# --- Error codes (all exit 1) ---
# E0xx: generic errors
readonly ERR_MISSING_PARAM="E001"
readonly ERR_UNKNOWN_PARAM="E002"
# E1xx: parameter validation (per-flag)
readonly ERR_INVALID_SUBJECT_OWNER="E100"
readonly ERR_INVALID_SUBJECT_REPO="E101"
readonly ERR_INVALID_SUBJECT_NUMBER="E102"
readonly ERR_INVALID_TARGET_OWNER="E103"
readonly ERR_INVALID_TARGET_REPO="E104"
readonly ERR_INVALID_TARGET_NUMBER="E105"
readonly ERR_INVALID_RELATIONSHIP="E106"
readonly ERR_SAME_ISSUE="E107"
# E2xx: runtime errors
readonly ERR_SUBJECT_NODE_LOOKUP="E200"
readonly ERR_TARGET_NODE_LOOKUP="E201"
readonly ERR_EMPTY_SUBJECT_NODE_ID="E202"
readonly ERR_EMPTY_TARGET_NODE_ID="E203"
readonly ERR_MUTATION="E204"

# --- Defaults ---
subject_owner=""
subject_repo=""
subject_number=""
target_owner=""
target_repo=""
target_number=""
relationship=""

# --- Parse arguments ---
while [ $# -gt 0 ]; do
  case "$1" in
    --subject-owner)
      [ $# -ge 2 ] || { echo "link-dependency $ERR_INVALID_SUBJECT_OWNER error: --subject-owner requires a value" >&2; exit 1; }
      subject_owner="$2"
      shift 2
      ;;
    --subject-repo)
      [ $# -ge 2 ] || { echo "link-dependency $ERR_INVALID_SUBJECT_REPO error: --subject-repo requires a value" >&2; exit 1; }
      subject_repo="$2"
      shift 2
      ;;
    --subject-number)
      [ $# -ge 2 ] || { echo "link-dependency $ERR_INVALID_SUBJECT_NUMBER error: --subject-number requires a value" >&2; exit 1; }
      subject_number="$2"
      shift 2
      ;;
    --target-owner)
      [ $# -ge 2 ] || { echo "link-dependency $ERR_INVALID_TARGET_OWNER error: --target-owner requires a value" >&2; exit 1; }
      target_owner="$2"
      shift 2
      ;;
    --target-repo)
      [ $# -ge 2 ] || { echo "link-dependency $ERR_INVALID_TARGET_REPO error: --target-repo requires a value" >&2; exit 1; }
      target_repo="$2"
      shift 2
      ;;
    --target-number)
      [ $# -ge 2 ] || { echo "link-dependency $ERR_INVALID_TARGET_NUMBER error: --target-number requires a value" >&2; exit 1; }
      target_number="$2"
      shift 2
      ;;
    --relationship)
      [ $# -ge 2 ] || { echo "link-dependency $ERR_INVALID_RELATIONSHIP error: --relationship requires a value" >&2; exit 1; }
      relationship="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    --*)
      echo "link-dependency $ERR_UNKNOWN_PARAM error: unknown parameter '$1'" >&2
      exit 1
      ;;
    *)
      echo "link-dependency $ERR_UNKNOWN_PARAM error: unexpected parameter '$1'" >&2
      exit 1
      ;;
  esac
done

# --- Validate required flags ---
missing=()
[ -n "$subject_owner" ]  || missing+=("--subject-owner")
[ -n "$subject_repo" ]   || missing+=("--subject-repo")
[ -n "$subject_number" ] || missing+=("--subject-number")
[ -n "$target_owner" ]   || missing+=("--target-owner")
[ -n "$target_repo" ]    || missing+=("--target-repo")
[ -n "$target_number" ]  || missing+=("--target-number")
[ -n "$relationship" ]   || missing+=("--relationship")

if [ ${#missing[@]} -gt 0 ]; then
  echo "link-dependency $ERR_MISSING_PARAM error: missing required parameter(s): ${missing[*]}" >&2
  exit 1
fi

# --- Validate numbers ---
if ! [[ "$subject_number" =~ ^[0-9]+$ ]]; then
  echo "link-dependency $ERR_INVALID_SUBJECT_NUMBER error: --subject-number must be a positive integer (got '$subject_number')" >&2
  exit 1
fi

if ! [[ "$target_number" =~ ^[0-9]+$ ]]; then
  echo "link-dependency $ERR_INVALID_TARGET_NUMBER error: --target-number must be a positive integer (got '$target_number')" >&2
  exit 1
fi

# --- Validate relationship ---
case "$relationship" in
  blocked-by|is-blocking) ;;
  *)
    echo "link-dependency $ERR_INVALID_RELATIONSHIP error: --relationship must be 'blocked-by' or 'is-blocking' (got '$relationship')" >&2
    exit 1
    ;;
esac

# --- Validate not the same issue ---
if [ "$subject_owner" = "$target_owner" ] && [ "$subject_repo" = "$target_repo" ] && [ "$subject_number" = "$target_number" ]; then
  echo "link-dependency $ERR_SAME_ISSUE error: subject and target are the same issue (#$subject_number). An issue cannot depend on itself." >&2
  exit 1
fi

# --- Temp files for GraphQL payloads ---
subject_payload="$(mktemp "${TMPDIR:-/tmp}/link-dependency.subject.XXXXXX.json")"
target_payload="$(mktemp "${TMPDIR:-/tmp}/link-dependency.target.XXXXXX.json")"
mutation_payload="$(mktemp "${TMPDIR:-/tmp}/link-dependency.mutation.XXXXXX.json")"
trap 'rm -f "$subject_payload" "$target_payload" "$mutation_payload"' EXIT

# --- Step 1: Fetch subject node ID ---
jq -n \
  --arg owner "$subject_owner" \
  --arg repo "$subject_repo" \
  --argjson number "$subject_number" \
  '{"query": "query($owner: String!, $repo: String!, $number: Int!) { repository(owner: $owner, name: $repo) { issue(number: $number) { id } } }", "variables": {"owner": $owner, "repo": $repo, "number": $number}}' \
  > "$subject_payload"

SUBJECT_RESULT=$(gh api graphql --input "$subject_payload" 2>&1) || {
  echo "link-dependency $ERR_SUBJECT_NODE_LOOKUP error: subject node ID lookup failed — $SUBJECT_RESULT" >&2
  exit 1
}

SUBJECT_NODE_ID=$(echo "$SUBJECT_RESULT" | jq -r '.data.repository.issue.id // empty')

if [ -z "$SUBJECT_NODE_ID" ]; then
  echo "link-dependency $ERR_EMPTY_SUBJECT_NODE_ID error: could not resolve node ID for subject issue #$subject_number in $subject_owner/$subject_repo" >&2
  exit 1
fi

# --- Step 2: Fetch target node ID ---
# When subject and target are in the same repo, we could reuse the first query.
# For simplicity (and because addBlockedBy needs both IDs anyway), always query
# separately. This handles cross-repo without special-casing.

jq -n \
  --arg owner "$target_owner" \
  --arg repo "$target_repo" \
  --argjson number "$target_number" \
  '{"query": "query($owner: String!, $repo: String!, $number: Int!) { repository(owner: $owner, name: $repo) { issue(number: $number) { id } } }", "variables": {"owner": $owner, "repo": $repo, "number": $number}}' \
  > "$target_payload"

TARGET_RESULT=$(gh api graphql --input "$target_payload" 2>&1) || {
  echo "link-dependency $ERR_TARGET_NODE_LOOKUP error: target node ID lookup failed — $TARGET_RESULT" >&2
  exit 1
}

TARGET_NODE_ID=$(echo "$TARGET_RESULT" | jq -r '.data.repository.issue.id // empty')

if [ -z "$TARGET_NODE_ID" ]; then
  echo "link-dependency $ERR_EMPTY_TARGET_NODE_ID error: could not resolve node ID for target issue #$target_number in $target_owner/$target_repo" >&2
  exit 1
fi

# --- Step 3: Call addBlockedBy mutation ---
# Map relationship to addBlockedBy argument order:
#   blocked-by:  subject IS blocked BY target   → issueId=subject, blockingIssueId=target
#   is-blocking: subject IS blocking target     → issueId=target, blockingIssueId=subject
if [ "$relationship" = "blocked-by" ]; then
  issue_id="$SUBJECT_NODE_ID"
  blocking_id="$TARGET_NODE_ID"
  label="blocked #$subject_number ← #$target_number"
else
  issue_id="$TARGET_NODE_ID"
  blocking_id="$SUBJECT_NODE_ID"
  label="blocking #$subject_number → #$target_number"
fi

jq -n \
  --arg issueId "$issue_id" \
  --arg blockingId "$blocking_id" \
  '{"query": "mutation($issueId: ID!, $blockingId: ID!) { addBlockedBy(input: {issueId: $issueId, blockingIssueId: $blockingId}) { issue { number } blockingIssue { number } } }", "variables": {"issueId": $issueId, "blockingId": $blockingId}}' \
  > "$mutation_payload"

RESULT=$(gh api graphql --input "$mutation_payload" 2>&1) || {
  echo "link-dependency $ERR_MUTATION error: addBlockedBy mutation failed — $RESULT" >&2
  exit 1
}

# Check for GraphQL-level errors in the response
ERRORS=$(echo "$RESULT" | jq -r '.errors[0].message // empty')
if [ -n "$ERRORS" ]; then
  echo "link-dependency $ERR_MUTATION error: $ERRORS" >&2
  exit 1
fi

echo "$label"
