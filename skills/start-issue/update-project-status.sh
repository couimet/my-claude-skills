#!/usr/bin/env bash
set -euo pipefail

# update-project-status.sh — Detect GitHub Projects V2 membership and move issue to "In Progress".
#
# Usage: update-project-status.sh <owner> <repo> <issue_number>
#
# Queries the issue's project items via GraphQL. For each item with a Status field
# that is not already "In Progress", runs the updateProjectV2ItemFieldValue mutation
# and posts an issue comment documenting the transition.
#
# Exits 0 on success or if no action needed. Never fails the parent skill.

OWNER="$1"
REPO="$2"
ISSUE_NUMBER="$3"

# Quick guard: skip if gh or jq are missing (should never happen, but safe)
command -v gh >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Query project items for this issue. Exit silently on any failure.
RESULT=$(gh api graphql -f query="
  query {
    repository(owner: \"$OWNER\", name: \"$REPO\") {
      issue(number: $ISSUE_NUMBER) {
        projectItems(first: 20) {
          nodes {
            id
            project { id title }
            fieldValueByName(name: \"Status\") {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field {
                  ... on ProjectV2SingleSelectField {
                    id
                    name
                    options { id name }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
" 2>/dev/null) || exit 0

# Extract items that need updating: have a Status field, not already "In Progress",
# and have an "In Progress" option available.
echo "$RESULT" | jq -c '
  .data.repository.issue.projectItems.nodes[] |
  select(.fieldValueByName != null) |
  select((.fieldValueByName.name | ascii_downcase) != "in progress") |
  . as $item |
  ($item.fieldValueByName.field.options[] | select((.name | ascii_downcase) == "in progress") | .id) as $optionId |
  {
    itemId: $item.id,
    projectId: $item.project.id,
    projectTitle: $item.project.title,
    fieldId: $item.fieldValueByName.field.id,
    currentStatus: $item.fieldValueByName.name,
    inProgressOptionId: $optionId
  }
' 2>/dev/null | while IFS= read -r ITEM_JSON; do

  ITEM_ID=$(echo "$ITEM_JSON" | jq -r '.itemId')
  PROJECT_ID=$(echo "$ITEM_JSON" | jq -r '.projectId')
  PROJECT_TITLE=$(echo "$ITEM_JSON" | jq -r '.projectTitle')
  FIELD_ID=$(echo "$ITEM_JSON" | jq -r '.fieldId')
  CURRENT_STATUS=$(echo "$ITEM_JSON" | jq -r '.currentStatus')
  OPTION_ID=$(echo "$ITEM_JSON" | jq -r '.inProgressOptionId')

  if [ "$OPTION_ID" = "null" ] || [ -z "$OPTION_ID" ]; then
    continue
  fi

  # Update the project item status
  gh api graphql -f query="
    mutation {
      updateProjectV2ItemFieldValue(input: {
        projectId: \"$PROJECT_ID\",
        itemId: \"$ITEM_ID\",
        fieldId: \"$FIELD_ID\",
        value: {singleSelectOptionId: \"$OPTION_ID\"}
      }) {
        clientMutationId
      }
    }
  " >/dev/null 2>&1 || continue

  # Document the transition with an issue comment
  PREVIOUS="${CURRENT_STATUS:-No Status}"
  gh issue comment "$ISSUE_NUMBER" \
    --repo "$OWNER/$REPO" \
    --body "Moved Status from \`$PREVIOUS\` to \`In Progress\` on project **$PROJECT_TITLE**." \
    >/dev/null 2>&1 || true

  echo "Project \"$PROJECT_TITLE\": moved Status from \"$PREVIOUS\" to \"In Progress\""
done
