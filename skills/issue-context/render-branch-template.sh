#!/usr/bin/env bash
#
# render-branch-template.sh — Print a branch name built from the configured
# branchTemplate and an identifier.
#
# Usage: render-branch-template.sh <identifier>
#
# Prints SETTINGS_BRANCH_TEMPLATE with every `{id}` placeholder replaced by
# the identifier. Branch creation and branch-issue-id.sh's branch matching
# must stay in lockstep: branchTemplate and branchPatterns are a paired
# configuration, so the rendered branch is parsed back through the same shared
# matcher (issue-settings.sh) and must resolve to the identifier it was built
# from. A rendered branch the configured branchPatterns cannot re-parse to the
# same identifier (a template-only override such as `work/{id}` under patterns
# that only match `issues/...`, or a template whose capture falls short of the
# full identifier) is rejected with an error before any branch is created.
# When the configured template is unset or contains no `{id}` placeholder the
# built-in default `issues/{id}` is substituted instead, mirroring how branch
# matching falls back to the default branchPatterns. The identifier must be
# usable as a single path component (it is interpolated verbatim into the
# branch name); an unsafe identifier prints an error to stderr and exits 1.
#
# Settings come from issue-settings.sh (see MY_CLAUDE_SKILLS_CONFIG).

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/issue-settings.sh"

_main() {
  local identifier="$1"
  local template rendered

  if ! _issue_settings_is_safe_component "$identifier"; then
    echo "render-branch-template: error: '$identifier' is not usable as a work-item identifier" >&2
    return 1
  fi

  template="${SETTINGS_BRANCH_TEMPLATE:-}"
  if [ -z "$template" ] || [[ "$template" != *"{id}"* ]]; then
    template="issues/{id}"
  fi
  rendered="${template//\{id\}/$identifier}"
  # The rendered branch must parse back to the same identifier under the
  # configured branchPatterns: branchTemplate and branchPatterns are a paired
  # configuration, and a branch this script emits that branch-issue-id.sh
  # cannot re-parse (or parses to a different id) would be created by
  # /start-issue and then treated as a non-work branch.
  recaptured="$(_issue_settings_branch_identifier "$rendered")" || recaptured=""
  if [ -z "$recaptured" ] || [ "$recaptured" != "$identifier" ]; then
    echo "render-branch-template: error: branchTemplate '$template' renders '$rendered', which does not parse back to identifier '$identifier' under the configured branchPatterns; branchTemplate and branchPatterns must be a paired configuration" >&2
    return 1
  fi
  printf '%s\n' "$rendered"
}

if [ "$#" -eq 1 ]; then
  _main "$1"
else
  echo "usage: render-branch-template.sh <identifier>" >&2
  exit 1
fi
