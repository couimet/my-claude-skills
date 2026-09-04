#!/usr/bin/env bash
#
# link-sub-issue.sh — Link a GitHub issue as a sub-issue of a parent issue.
#
# Usage: link-sub-issue.sh --owner OWNER --repo REPO --parent NUMBER --child NUMBER
#        [--child-owner OWNER] [--child-repo REPO]
#
#   --owner         Repository owner (username or organization)
#   --repo          Repository name
#   --parent        Parent issue number
#   --child         Child issue number to link as sub-issue
#   --child-owner   Child repository owner (default: --owner)
#   --child-repo    Child repository name (default: --repo)
#
# The child is resolved in its own repository, so a child created in a
# different repository than the parent (cross-repository sub-issues) still
# links correctly. The parent resolves in --owner/--repo, the child in
# --child-owner/--child-repo.
#
# Uses jq -n to build GraphQL payloads via temp files, avoiding zsh history
# expansion that silently strips ! from type annotations (String!, Int!, ID!)
# inside $() command substitutions.
#
# Output: "linked #<child> → #<parent>" on success, error message on failure.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: link-sub-issue.sh --owner OWNER --repo REPO --parent NUMBER --child NUMBER [--child-owner OWNER] [--child-repo REPO]

  --owner         Repository owner (username or organization)
  --repo          Repository name
  --parent        Parent issue number
  --child         Child issue number to link as sub-issue
  --child-owner   Child repository owner (default: --owner)
  --child-repo    Child repository name (default: --repo)
  --help          Show this help message
EOF
}

# --- Error codes (all exit 1) ---
# E0xx: generic errors
readonly ERR_MISSING_PARAM="E001"
readonly ERR_UNKNOWN_PARAM="E002"
# E1xx: parameter validation (per-flag)
readonly ERR_INVALID_OWNER="E100"
readonly ERR_INVALID_REPO="E101"
readonly ERR_INVALID_PARENT="E102"
readonly ERR_INVALID_CHILD="E103"
readonly ERR_INVALID_CHILD_OWNER="E104"
readonly ERR_INVALID_CHILD_REPO="E105"
# E2xx: runtime errors
readonly ERR_NODE_LOOKUP="E200"
readonly ERR_EMPTY_NODE_ID="E201"
readonly ERR_MUTATION="E202"

# --- Defaults ---
owner=""
repo=""
parent=""
child=""
child_owner=""
child_repo=""

# --- Parse arguments ---
while [ $# -gt 0 ]; do
  case "$1" in
    --owner)
      [ $# -ge 2 ] || { echo "link-sub-issue $ERR_INVALID_OWNER error: --owner requires a value" >&2; exit 1; }
      owner="$2"
      shift 2
      ;;
    --repo)
      [ $# -ge 2 ] || { echo "link-sub-issue $ERR_INVALID_REPO error: --repo requires a value" >&2; exit 1; }
      repo="$2"
      shift 2
      ;;
    --parent)
      [ $# -ge 2 ] || { echo "link-sub-issue $ERR_INVALID_PARENT error: --parent requires a value" >&2; exit 1; }
      parent="$2"
      shift 2
      ;;
    --child)
      [ $# -ge 2 ] || { echo "link-sub-issue $ERR_INVALID_CHILD error: --child requires a value" >&2; exit 1; }
      child="$2"
      shift 2
      ;;
    --child-owner)
      [ $# -ge 2 ] || { echo "link-sub-issue $ERR_INVALID_CHILD_OWNER error: --child-owner requires a value" >&2; exit 1; }
      child_owner="$2"
      shift 2
      ;;
    --child-repo)
      [ $# -ge 2 ] || { echo "link-sub-issue $ERR_INVALID_CHILD_REPO error: --child-repo requires a value" >&2; exit 1; }
      child_repo="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    --*)
      echo "link-sub-issue $ERR_UNKNOWN_PARAM error: unknown parameter '$1'" >&2
      exit 1
      ;;
    *)
      echo "link-sub-issue $ERR_UNKNOWN_PARAM error: unexpected parameter '$1'" >&2
      exit 1
      ;;
  esac
done

# --- Validate required flags ---
missing=()
[ -n "$owner" ]  || missing+=("--owner")
[ -n "$repo" ]   || missing+=("--repo")
[ -n "$parent" ] || missing+=("--parent")
[ -n "$child" ]  || missing+=("--child")

if [ ${#missing[@]} -gt 0 ]; then
  echo "link-sub-issue $ERR_MISSING_PARAM error: missing required parameter(s): ${missing[*]}" >&2
  exit 1
fi

# --- Validate numbers ---
if ! [[ "$parent" =~ ^[0-9]+$ ]]; then
  echo "link-sub-issue $ERR_INVALID_PARENT error: --parent must be a positive integer (got '$parent')" >&2
  exit 1
fi

if ! [[ "$child" =~ ^[0-9]+$ ]]; then
  echo "link-sub-issue $ERR_INVALID_CHILD error: --child must be a positive integer (got '$child')" >&2
  exit 1
fi

# --- Default child repo to the parent's repo when not given ---
: "${child_owner:=$owner}"
: "${child_repo:=$repo}"

# --- Temp files for GraphQL payloads ---
nodes_payload="$(mktemp "${TMPDIR:-/tmp}/link-sub-issue.nodes.XXXXXX.json")"
mutation_payload="$(mktemp "${TMPDIR:-/tmp}/link-sub-issue.mutation.XXXXXX.json")"
trap 'rm -f "$nodes_payload" "$mutation_payload"' EXIT

# --- Step 1: Fetch node IDs ---
jq -n \
  --arg owner "$owner" \
  --arg repo "$repo" \
  --argjson parent "$parent" \
  --arg childOwner "$child_owner" \
  --arg childRepo "$child_repo" \
  --argjson child "$child" \
  '{"query": "query($owner: String!, $repo: String!, $parent: Int!, $childOwner: String!, $childRepo: String!, $child: Int!) { repository(owner: $owner, name: $repo) { parent: issue(number: $parent) { id } } childRepository: repository(owner: $childOwner, name: $childRepo) { child: issue(number: $child) { id } } }", "variables": {"owner": $owner, "repo": $repo, "parent": $parent, "childOwner": $childOwner, "childRepo": $childRepo, "child": $child}}' \
  > "$nodes_payload"

NODES=$(gh api graphql -H 'GraphQL-Features: sub_issues' --input "$nodes_payload" 2>&1) || {
  echo "link-sub-issue $ERR_NODE_LOOKUP error: node ID lookup failed — $NODES" >&2
  exit 1
}

PARENT_NODE_ID=$(echo "$NODES" | jq -r '.data.repository.parent.id // empty')
CHILD_NODE_ID=$(echo "$NODES" | jq -r '.data.childRepository.child.id // empty')

if [ -z "$PARENT_NODE_ID" ]; then
  echo "link-sub-issue $ERR_EMPTY_NODE_ID error: could not resolve node ID for parent issue #$parent" >&2
  exit 1
fi

if [ -z "$CHILD_NODE_ID" ]; then
  echo "link-sub-issue $ERR_EMPTY_NODE_ID error: could not resolve node ID for child issue #$child" >&2
  exit 1
fi

# --- Step 2: Link sub-issue ---
jq -n \
  --arg parentId "$PARENT_NODE_ID" \
  --arg childId "$CHILD_NODE_ID" \
  '{"query": "mutation($parentId: ID!, $childId: ID!) { addSubIssue(input: {issueId: $parentId, subIssueId: $childId}) { issue { number title } subIssue { number title } } }", "variables": {"parentId": $parentId, "childId": $childId}}' \
  > "$mutation_payload"

RESULT=$(gh api graphql -H 'GraphQL-Features: sub_issues' --input "$mutation_payload" 2>&1) || {
  echo "link-sub-issue $ERR_MUTATION error: addSubIssue mutation failed — $RESULT" >&2
  exit 1
}

# Check for GraphQL-level errors in the response
ERRORS=$(echo "$RESULT" | jq -r '.errors[0].message // empty')
if [ -n "$ERRORS" ]; then
  echo "link-sub-issue $ERR_MUTATION error: $ERRORS" >&2
  exit 1
fi

echo "linked #$child → #$parent"
