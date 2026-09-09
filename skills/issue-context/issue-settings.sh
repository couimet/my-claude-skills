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
#   identifierCase   "upper"        case a tracker-key-shaped identifier is
#                                   folded to; "upper", "lower", "preserve"
#   version          1              schema version
#
# Globals set on return:
#   SETTINGS_VERSION
#   SETTINGS_SEGMENT
#   SETTINGS_BRANCH_TEMPLATE
#   SETTINGS_BRANCH_PATTERNS   (array)
#   SETTINGS_URL_PATTERNS      (array)
#   SETTINGS_IDENTIFIER_CASE
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
    '/browse/([A-Za-z][A-Za-z0-9]+-[0-9]+)'
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

# is_safe_component <value> — 0 when <value> can be one path component and one
# branch segment: non-empty, not "." or "..", contains no "/" (no internal
# components), no whitespace, and no leading or trailing dot. The segment and
# every resolved identifier pass through this predicate before they are
# interpolated into a .claude-work/ path.
_issue_settings_is_safe_component() {
  local value="$1"
  [ -n "$value" ] || return 1
  case "$value" in
    . | ..) return 1 ;;
  esac
  case "$value" in
    */*) return 1 ;;
  esac
  case "$value" in
    *[[:space:]]*) return 1 ;;
  esac
  case "$value" in
    .* | *.) return 1 ;;
  esac
  return 0
}

# is_key_shaped <value> — 0 when <value> has the shape of a tracker key: one
# leading letter, then alphanumerics, then a hyphen and digits. Normalisation
# is guarded by this shape so numeric identifiers (which carry no case) and the
# free-form slugs the `^issues/(.+)$` catch-all admits pass through untouched;
# a blanket fold would turn `issues/my-feature` into `MY-FEATURE`. A slug that
# happens to take this shape, `release-2` for instance, is folded; that is the
# accepted cost of the guard, and identifierCase "preserve" is the escape.
_issue_settings_identifier_is_key_shaped() {
  [[ "$1" =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+$ ]]
}

# normalize_identifier <value> — Print <value> folded to the configured
# identifierCase, unchanged when it is not key-shaped or the configured case is
# "preserve". Every boundary that emits an identifier folds through here, so a
# work item reached through a branch, a bare identifier, or a tracker URL
# resolves to one spelling and therefore one .claude-work/ folder. Uses tr
# rather than ${value^^}: that expansion is bash 4 only and macOS ships 3.2.
_issue_settings_normalize_identifier() {
  local value="$1"
  if ! _issue_settings_identifier_is_key_shaped "$value"; then
    printf '%s' "$value"
    return 0
  fi
  case "$SETTINGS_IDENTIFIER_CASE" in
    upper) printf '%s' "$value" | tr '[:lower:]' '[:upper:]' ;;
    lower) printf '%s' "$value" | tr '[:upper:]' '[:lower:]' ;;
    *) printf '%s' "$value" ;;
  esac
}

# branch_identifier <branch> — Print the work-item identifier <branch> resolves
# to under the configured branchPatterns, or exit 1 silently when no pattern
# yields a usable capture. The first pattern whose capture group one is
# non-empty and usable as one path component wins; a branch that matches a
# pattern but captures nothing usable falls through to later patterns. This is
# the single matching routine shared by branch-issue-id.sh (which matches the
# current branch) and render-branch-template.sh (which parses a branch it just
# rendered back under the same patterns), so branch creation and branch
# matching cannot drift apart. Uses return, not exit: this file is sourced.
_issue_settings_branch_identifier() {
  local branch="$1" pattern identifier
  for pattern in "${SETTINGS_BRANCH_PATTERNS[@]}"; do
    if [[ "$branch" =~ $pattern ]]; then
      identifier="$(_issue_settings_normalize_identifier "${BASH_REMATCH[1]:-}")"
      if [ -n "$identifier" ] \
          && _issue_settings_is_safe_component "$identifier"; then
        printf '%s\n' "$identifier"
        return 0
      fi
      # Matched but captured nothing usable (empty or unsafe); keep trying
      # later patterns.
    fi
  done
  return 1
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

# Load an array key. A non-array value, a member that is not a JSON string
# (numbers, booleans, and null would otherwise be coerced to "42", "true",
# "null" by jq -r and pass the regex check as one wrong pattern), or an invalid
# regex entry fall back to the defaults for that key, per the failure policy.
_issue_settings_read_patterns() {
  local json="$1" key="$2" default_fn="$3"
  local candidate=() entry all_strings
  if printf '%s' "$json" | jq -e --arg k "$key" '(has($k) and (.[$k] | type == "array"))' >/dev/null 2>&1; then
    all_strings="$(printf '%s' "$json" | jq -r --arg k "$key" 'all(.[$k][]; type == "string")')"
    if [ "$all_strings" != "true" ]; then
      echo "issue-settings: warning: ${key} contains a non-string entry; using default ${key}" >&2
    else
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
  SETTINGS_IDENTIFIER_CASE="upper"
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
      # An empty segment is honored (omits the directory); any other value must
      # be one safe path component or the folder resolver could escape
      # .claude-work/, so fall back to the default on an unsafe segment.
      if [ -n "$SETTINGS_SEGMENT" ] && ! _issue_settings_is_safe_component "$SETTINGS_SEGMENT"; then
        echo "issue-settings: warning: invalid segment '$SETTINGS_SEGMENT'; using default segment 'issues'" >&2
        SETTINGS_SEGMENT="issues"
      fi
      # shellcheck disable=SC2034
      SETTINGS_BRANCH_TEMPLATE="$(_issue_settings_read_scalar "$_issue_settings_json" branchTemplate 'issues/{id}')"
      # shellcheck disable=SC2034
      SETTINGS_IDENTIFIER_CASE="$(_issue_settings_read_scalar "$_issue_settings_json" identifierCase upper)"
      # Only the three documented values fold predictably; anything else would
      # silently behave as "preserve" and reintroduce the split this key exists
      # to close, so warn and fall back to the default.
      case "$SETTINGS_IDENTIFIER_CASE" in
        upper | lower | preserve) ;;
        "")
          # An empty value reads as "unset", the same way an empty
          # branchTemplate falls back to its default. Silent, because there is
          # nothing to report: no value was expressed.
          SETTINGS_IDENTIFIER_CASE="upper"
          ;;
        *)
          echo "issue-settings: warning: invalid identifierCase '$SETTINGS_IDENTIFIER_CASE'; using default identifierCase 'upper'" >&2
          SETTINGS_IDENTIFIER_CASE="upper"
          ;;
      esac
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
