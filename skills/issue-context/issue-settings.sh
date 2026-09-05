#!/usr/bin/env bash
#
# issue-settings.sh — Locate and parse the work-item settings file and expose
# the result as globals consumers read. Source this file; do not execute it.
#
# Settings live at ~/.my-claude-skills/settings.json. The path is overridable
# with MY_CLAUDE_SKILLS_CONFIG, which must hold a full path to the file. The
# override is required rather than convenient: the bats suite creates a temp
# directory but never isolates HOME, so tests set the override to a temp file
# to keep a developer's personal settings from changing their outcome.
#
# Keys and built-in defaults:
#   segment          "issues"       directory between the root and the
#                                   identifier; an empty value omits it
#   branchPatterns   the list below ordered regexes, first match wins,
#                                   capture group one is the identifier
#   branchTemplate   "issues/{id}"  builds a branch name from an identifier;
#                                   a regex cannot be inverted, so reading and
#                                   writing need separate keys
#   urlPatterns      the list below ordered regexes matched against a tracker
#                                   URL, first match wins, capture one is id
#   version          1              schema version
#
# Globals set on return:
#   SETTINGS_VERSION
#   SETTINGS_SEGMENT
#   SETTINGS_BRANCH_TEMPLATE
#   SETTINGS_BRANCH_PATTERNS   (array)
#   SETTINGS_URL_PATTERNS      (array)
#   SETTINGS_FILE              the resolved config path
#
# Failure policy: every failure falls back to the built-in defaults and the
# caller continues. A missing or unreadable file at the default path is normal
# and silent. A missing or unreadable file named by MY_CLAUDE_SKILLS_CONFIG is
# a user error and warns. Malformed JSON, a non-object document, or an invalid
# regex entry warns and falls back, per key, to defaults.

_issue_settings_default_branch_patterns() {
  printf '%s\n' \
    '^issues/([0-9]+)[-_]' \
    '^issues/([0-9]+)$' \
    '^issues/([A-Za-z][A-Za-z0-9]*-[0-9]+)' \
    '^issues/(.+)$' \
    '^([A-Za-z][A-Za-z0-9]*-[0-9]+)'
}

_issue_settings_default_url_patterns() {
  printf '%s\n' \
    '/issues/([0-9]+)' \
    '/browse/([A-Z][A-Z0-9]+-[0-9]+)'
}

_issue_settings_is_valid_regex() {
  local re="$1"
  [ -n "$re" ] || return 1
  # Bash reports exit 2 when the right-hand side fails to compile as an ERE;
  # 0 (probe matched) and 1 (probe did not match) both mean it compiled.
  [[ "_" =~ $re ]] 2>/dev/null
  local rc=$?
  [ "$rc" -ne 2 ]
}

# Resolve the config path.
_issue_settings_file="${MY_CLAUDE_SKILLS_CONFIG:-${HOME:-}/.my-claude-skills/settings.json}"
SETTINGS_FILE="$_issue_settings_file"

# Load a scalar key, falling back to the default when the key is absent, null,
# or not a string. An explicit empty string is honored (segment "" means
# "omit the segment directory").
_issue_settings_read_scalar() {
  local json="$1" key="$2" default="$3"
  printf '%s' "$json" | jq -r --arg k "$key" --arg d "$default" \
    'if has($k) and (.[$k] | type == "string") then .[$k] else $d end'
}

# Load an array key. Invalid regex entries or a non-array value fall back to
# the defaults for that key, per the failure policy.
_issue_settings_read_patterns() {
  local json="$1" key="$2" default_fn="$3"
  local candidate=() entry
  if printf '%s' "$json" | jq -e --arg k "$key" '(has($k) and (.[$k] | type == "array"))' >/dev/null 2>&1; then
    while IFS= read -r entry; do
      candidate+=("$entry")
    done < <(printf '%s' "$json" | jq -r --arg k "$key" '.[$k][]')
    for entry in "${candidate[@]}"; do
      if ! _issue_settings_is_valid_regex "$entry"; then
        echo "issue-settings: warning: invalid regex in ${key}: '$entry'; using default ${key}" >&2
        candidate=()
        break
      fi
    done
    if [ "${#candidate[@]}" -gt 0 ]; then
      printf '%s\n' "${candidate[@]}"
      return 0
    fi
  fi
  # Fall through to the built-in default list.
  while IFS= read -r entry; do
    printf '%s\n' "$entry"
  done < <("$default_fn")
}

_issue_settings_apply_defaults() {
  SETTINGS_VERSION="1"
  SETTINGS_SEGMENT="issues"
  SETTINGS_BRANCH_TEMPLATE="issues/{id}"
  SETTINGS_BRANCH_PATTERNS=()
  while IFS= read -r _issue_settings_entry; do
    SETTINGS_BRANCH_PATTERNS+=("$_issue_settings_entry")
  done < <(_issue_settings_default_branch_patterns)
  SETTINGS_URL_PATTERNS=()
  while IFS= read -r _issue_settings_entry; do
    SETTINGS_URL_PATTERNS+=("$_issue_settings_entry")
  done < <(_issue_settings_default_url_patterns)
  unset _issue_settings_entry
}

# --- Load ---
_issue_settings_json=""
if [ -f "$_issue_settings_file" ] && [ -r "$_issue_settings_file" ]; then
  if command -v jq >/dev/null 2>&1; then
    if _issue_settings_json="$(jq -c . "$_issue_settings_file" 2>/dev/null)" \
        && [ -n "$_issue_settings_json" ] \
        && printf '%s' "$_issue_settings_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
      # Valid object document: overlay defaults per key.
      # The SETTINGS_* globals are the file's contract; they are read by the
      # scripts that source this file, never here, so shellcheck sees them as
      # unused.
      # shellcheck disable=SC2034
      SETTINGS_VERSION="$(_issue_settings_read_scalar "$_issue_settings_json" version 1)"
      # shellcheck disable=SC2034
      SETTINGS_SEGMENT="$(_issue_settings_read_scalar "$_issue_settings_json" segment issues)"
      # shellcheck disable=SC2034
      SETTINGS_BRANCH_TEMPLATE="$(_issue_settings_read_scalar "$_issue_settings_json" branchTemplate 'issues/{id}')"
      SETTINGS_BRANCH_PATTERNS=()
      while IFS= read -r _issue_settings_entry; do
        SETTINGS_BRANCH_PATTERNS+=("$_issue_settings_entry")
      done < <(_issue_settings_read_patterns "$_issue_settings_json" branchPatterns _issue_settings_default_branch_patterns)
      SETTINGS_URL_PATTERNS=()
      while IFS= read -r _issue_settings_entry; do
        SETTINGS_URL_PATTERNS+=("$_issue_settings_entry")
      done < <(_issue_settings_read_patterns "$_issue_settings_json" urlPatterns _issue_settings_default_url_patterns)
      unset _issue_settings_entry
    else
      echo "issue-settings: warning: invalid settings document in $SETTINGS_FILE (malformed or not a JSON object); using defaults" >&2
      _issue_settings_apply_defaults
    fi
  else
    echo "issue-settings: warning: jq not found; cannot read $SETTINGS_FILE; using defaults" >&2
    _issue_settings_apply_defaults
  fi
else
  if [ -n "${MY_CLAUDE_SKILLS_CONFIG:-}" ]; then
    echo "issue-settings: warning: MY_CLAUDE_SKILLS_CONFIG file not readable: $SETTINGS_FILE; using defaults" >&2
  fi
  _issue_settings_apply_defaults
fi

unset _issue_settings_file _issue_settings_json
