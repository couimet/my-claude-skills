#!/usr/bin/env bash
#
# render-branch-template.sh — Print a branch name built from the configured
# branchTemplate and an identifier.
#
# Usage: render-branch-template.sh <identifier>
#
# Prints SETTINGS_BRANCH_TEMPLATE with every `{id}` placeholder replaced by
# the identifier. Branch creation and branch-issue-id.sh's branch matching
# must stay in lockstep, so both read the same settings file; when the
# configured template is unset or contains no `{id}` placeholder the built-in
# default `issues/{id}` is substituted instead, mirroring how branch matching
# falls back to the default branchPatterns. The identifier must be usable as a
# single path component (it is interpolated verbatim into the branch name);
# an unsafe identifier prints an error to stderr and exits 1.
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
  printf '%s\n' "$rendered"
}

if [ "$#" -eq 1 ]; then
  _main "$1"
else
  echo "usage: render-branch-template.sh <identifier>" >&2
  exit 1
fi
