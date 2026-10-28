#!/bin/bash
#
# install.sh — Link this repository's skills into ~/.claude/skills, then offer
# to add the Claude Code hook of the skills to ~/.claude/settings.json.
#
# Usage:
#   install.sh                   link the skills, then ask about the hook
#   install.sh --no-hooks        link the skills, and skip the hook step
#   install.sh --uninstall-hooks remove the hook entry, and change nothing else
#   install.sh --help
#
# The hook is skills/issue-context/session-hook.sh. It keeps the work folder
# of a session after a /clear, warns a resumed session when another session
# holds its folder, and keeps the session name equal to its folder name at
# each prompt; docs/ADR/006-claude-code-hooks.md says why. The
# plugin ships the same hook in hooks/hooks.json, so this step is for a user
# who installs with this script.
#
# The step changes the global settings file, so it asks first, and the
# default answer is no. With no answer on stdin it changes nothing and prints
# the entry to add by hand. The edit is idempotent: it removes each entry of
# this hook, then adds one entry for each event, and it keeps every other key.
# It writes a backup beside the file first, and it writes through a symlink,
# so a settings file that a dotfiles repository links stays a link. A file
# that is not a JSON object is never changed.
#
# The entry names the hook through the links, so install.sh checks that this
# path can run before it asks, and it changes nothing when it cannot. An
# entry that is already in the settings file but cannot run is reported, not
# passed as "already in".
#
# install.sh refuses to link from a linked git worktree, and names the main
# checkout to run it from. A worktree is ephemeral: when it is removed, each
# link into it breaks. --help and --uninstall-hooks make no links, so they
# run from any checkout.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install.sh [--no-hooks | --uninstall-hooks]
       install.sh --help

  --no-hooks         Link the skills, and skip the Claude Code hook step
  --uninstall-hooks  Remove the hook entry from ~/.claude/settings.json only
  --help             Show this help message
EOF
}

hooks_mode="ask"
case "${1-}" in
  "") ;;
  --no-hooks) hooks_mode="skip" ;;
  --uninstall-hooks) hooks_mode="uninstall" ;;
  --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    echo "install.sh: unknown argument '$1'" >&2
    exit 1
    ;;
esac
[ "$#" -le 1 ] || { usage >&2; echo "install.sh: expected at most one argument" >&2; exit 1; }

SKILLS_DIR="$HOME/.claude/skills"
SETTINGS="$HOME/.claude/settings.json"
HOOK_COMMAND="$SKILLS_DIR/issue-context/session-hook.sh"

# hook_filter — the jq definitions that find this hook's entries. An entry is
# this hook's when its command ends with the path below the skills directory,
# so a link to another checkout or a hand-written ~ path still counts.
# shellcheck disable=SC2016 # a jq program, not a shell expansion
HOOK_JQ_DEFS='
  def ours: ((.command // "") | tostring | endswith("/issue-context/session-hook.sh"));
  def strip: map(.hooks = ((.hooks // []) | map(select(ours | not))))
             | map(select((.hooks | length) > 0));
'

# write_settings <jq filter> — apply <jq filter> to the settings file after a
# backup. Prints the backup path. Returns 1, with the file unchanged, when the
# file is not a JSON object or a write fails.
write_settings() {
  local filter="$1" tmp backup
  if [ -e "$SETTINGS" ]; then
    jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1 || {
      echo "  $SETTINGS is not a JSON object, so it was not changed." >&2
      return 1
    }
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/install-settings.XXXXXX")" || return 1
  if [ -e "$SETTINGS" ]; then
    jq --arg cmd "$HOOK_COMMAND" "$HOOK_JQ_DEFS $filter" "$SETTINGS" > "$tmp" 2>/dev/null \
      || { rm -f "$tmp"; return 1; }
    backup="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
    cp -p "$SETTINGS" "$backup" || { rm -f "$tmp"; return 1; }
    echo "  Backup: $backup"
  else
    jq -n --arg cmd "$HOOK_COMMAND" "$HOOK_JQ_DEFS {} | $filter" > "$tmp" 2>/dev/null \
      || { rm -f "$tmp"; return 1; }
    mkdir -p "$(dirname "$SETTINGS")"
  fi
  # A redirect writes through a symlink, where mv would replace the link.
  cat "$tmp" > "$SETTINGS" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
}

print_hook_entry() {
  jq -n --arg cmd "$HOOK_COMMAND" '{hooks: {
    SessionStart: [{matcher: "clear|resume", hooks: [{type: "command", command: $cmd}]}],
    SessionEnd: [{matcher: "clear", hooks: [{type: "command", command: $cmd}]}],
    UserPromptSubmit: [{hooks: [{type: "command", command: $cmd}]}]}}' 2>/dev/null \
    | sed 's/^/    /'
}

# --- Remove the hook, and nothing else ---
if [ "$hooks_mode" = "uninstall" ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "install.sh: jq not found, so the hook entry was not removed from $SETTINGS" >&2
    exit 1
  fi
  if [ ! -e "$SETTINGS" ] \
      || ! jq -e "$HOOK_JQ_DEFS [(.hooks // {})[]?[]?.hooks[]? | select(ours)] | length > 0" \
        "$SETTINGS" >/dev/null 2>&1; then
    echo "No hook entry of my-claude-skills in $SETTINGS; nothing to remove."
    exit 0
  fi
  write_settings '
    if .hooks then
      .hooks |= (with_entries(.value |= strip) | with_entries(select(.value | length > 0)))
      | if (.hooks | length) == 0 then del(.hooks) else . end
    else . end' || { echo "install.sh: could not remove the hook entry from $SETTINGS" >&2; exit 1; }
  echo "Removed the hook entry of my-claude-skills from $SETTINGS."
  exit 0
fi

# Refuse a linked worktree, by where this script lives. In a linked worktree
# the git dir is <common dir>/worktrees/<name>, so the two paths differ; in
# the main checkout and outside git they are equal or absent.
script_dir="$(cd "$(dirname "$0")" && pwd)"
if git_dirs="$(git -C "$script_dir" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)"; then
  own_git_dir="${git_dirs%%$'\n'*}"
  common_git_dir="${git_dirs#*$'\n'}"
  if [ "$own_git_dir" != "$common_git_dir" ]; then
    main_checkout="$(dirname "$common_git_dir")"
    echo "install.sh: $script_dir is a linked git worktree, so nothing was linked." >&2
    echo "A worktree is ephemeral, and each link into it breaks when it is removed." >&2
    echo "Run install.sh from the main checkout: $main_checkout/install.sh" >&2
    exit 1
  fi
fi

REPO_DIR="$script_dir/skills"

# When invoked from a linked git worktree, resolve to the main checkout's
# skills/ directory instead so global symlinks survive worktree removal.
# git-common-dir is the shared .git directory; its parent is the main
# checkout root in all worktree configurations.
if git_common="$(git rev-parse --git-common-dir 2>/dev/null)"; then
  [[ "$git_common" == /* ]] || git_common="$PWD/$git_common"
  REPO_DIR="$(cd "$(dirname "$git_common")" && pwd -P)/skills"
fi

echo "Installing skills from $REPO_DIR → $SKILLS_DIR"

mkdir -p "$SKILLS_DIR"

installed=0
updated=0
unchanged=0
conflict=0

for skill_dir in "$REPO_DIR"/*/; do
  [ -d "$skill_dir" ] || continue
  name=$(basename "$skill_dir")
  target="$SKILLS_DIR/$name"
  source="${skill_dir%/}"

  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    unchanged=$((unchanged + 1))
    continue
  fi

  # The -e test below does not see a dangling symlink. Control would fall
  # through to `ln -s`, which fails with "File exists". set -e turns that
  # failure into a full abort. A link left from a previous checkout path is
  # this case. The prune after the loop cannot reach such a link, because its
  # stored target is not under the current REPO_DIR. Reclaim the link here.
  if [ -L "$target" ] && [ ! -e "$target" ]; then
    # Name the discarded target. Ownership of a dangling link is not knowable
    # from the link alone, so this reclaims a name something else may have
    # created; saying what was there is what makes that recoverable.
    previous="$(readlink "$target")"
    rm "$target"
    ln -s "$source" "$target"
    updated=$((updated + 1))
    echo "  ✓ $name (relinked; previous link pointed at $previous)"
    continue
  fi

  if [ -e "$target" ]; then
    if [ -L "$target" ]; then
      rm "$target"
      updated=$((updated + 1))
    elif [ -f "$target" ]; then
      echo "  WARNING: $target is a regular file (not a symlink). Skipping."
      echo "           Remove it manually if you want this skill managed by the repo."
      conflict=$((conflict + 1))
      continue
    elif [ -d "$target" ]; then
      echo "  WARNING: $target is a real directory (not a symlink). Skipping."
      echo "           Remove it manually if you want this skill managed by the repo."
      conflict=$((conflict + 1))
      continue
    fi
  else
    installed=$((installed + 1))
  fi

  ln -s "$source" "$target"
  echo "  ✓ $name"
done

# Prune links this installer created for skills the repo no longer ships.
# readlink still reports the stored target after that target is deleted, which
# is what makes a broken link attributable. Attribution is by shape, not by
# resolution: the `ln -s` above is only ever reached with a source globbed from
# REPO_DIR/*/, so every link this installer writes stores exactly
# REPO_DIR/<one component>. Requiring that exact shape is therefore the whole
# ownership test. It rejects a target that reaches outside through a symlink
# component, and one that escapes through `..`, without resolving either.
# Resolution is not available here in any case: a target that still resolved
# would not be a broken link, and neither realpath nor readlink -f is reliable
# in base macOS. A broken link of any other shape belongs to something this
# installer does not manage, so it is left alone even though it is equally
# broken.
pruned=0
for target in "$SKILLS_DIR"/*; do
  [ -L "$target" ] || continue
  [ ! -e "$target" ] || continue
  link_target="$(readlink "$target")"
  if [ "${link_target%/*}" != "$REPO_DIR" ]; then
    continue
  fi
  rm "$target"
  pruned=$((pruned + 1))
  echo "  ✗ $(basename "$target") (pruned; no longer in the repo)"
done

echo ""
echo "Done: $installed new, $updated updated, $unchanged unchanged, $pruned pruned, $conflict conflict(s)"
echo "Skills available as /skill-name in all Claude Code projects."
echo ""
echo "External skill dependencies (optional, installed separately):"
echo "  /asd-ste100  → npx skills add danyuchn/asd-ste100-skill --global"
echo "  /grilling    → npx skills add mattpocock/skills --global"
echo "Both are optional; this suite falls back to built-ins when they are missing."
echo ""
echo "Runtime command dependencies (commands the skills shell out to at runtime):"
echo "  jq  → brew install jq"
echo "jq parses the work-item settings file (~/.my-claude-skills/settings.json) the"
echo "path resolver reads. Without it the resolver uses its built-in defaults;"
echo "install jq to use a non-default configuration."

# --- The Claude Code hook ---
echo ""
if [ "$hooks_mode" = "skip" ]; then
  echo "Claude Code hook: skipped (--no-hooks)."
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Claude Code hook: jq not found, so $SETTINGS was not changed. Install jq and run install.sh again, or add this entry by hand:"
  echo "    {\"hooks\": {\"SessionStart\": [{\"matcher\": \"clear|resume\", \"hooks\": [{\"type\": \"command\", \"command\": \"$HOOK_COMMAND\"}]}], \"SessionEnd\": [{\"matcher\": \"clear\", \"hooks\": [{\"type\": \"command\", \"command\": \"$HOOK_COMMAND\"}]}], \"UserPromptSubmit\": [{\"hooks\": [{\"type\": \"command\", \"command\": \"$HOOK_COMMAND\"}]}]}}"
  exit 0
fi
already_in=0
if [ -e "$SETTINGS" ] && jq -e --arg cmd "$HOOK_COMMAND" "$HOOK_JQ_DEFS
    ([.hooks.SessionStart[]? | select(.matcher == \"clear|resume\") | .hooks[]? | select(.command == \$cmd)] | length == 1)
    and ([.hooks.SessionEnd[]? | select(.matcher == \"clear\") | .hooks[]? | select(.command == \$cmd)] | length == 1)
    and ([.hooks.UserPromptSubmit[]? | select(has(\"matcher\") | not) | .hooks[]? | select(.command == \$cmd)] | length == 1)
    and ([.hooks[]?[]?.hooks[]? | select(ours)] | length == 3)" "$SETTINGS" >/dev/null 2>&1; then
  already_in=1
fi
# Check the path that the entry names, through the links, because that is the
# path Claude Code runs. A checkout without the script gives an entry that
# fails at each session start.
if [ ! -x "$HOOK_COMMAND" ]; then
  if [ "$already_in" -eq 1 ]; then
    echo "Claude Code hook: in $SETTINGS, but $HOOK_COMMAND cannot run."
    echo "Update ${REPO_DIR%/skills} so it has the script, or remove the entry with install.sh --uninstall-hooks."
  else
    echo "Claude Code hook: not added, because $HOOK_COMMAND cannot run."
    echo "Update ${REPO_DIR%/skills} so it has the script, then run install.sh again."
  fi
  exit 0
fi
if [ "$already_in" -eq 1 ]; then
  echo "Claude Code hook: already in $SETTINGS."
  exit 0
fi

echo "Claude Code hook: the skills ship a hook that keeps the work folder of a session"
echo "after /clear, warns a resumed session when another session holds its folder, and"
echo "keeps the session name equal to its folder name at each prompt."
printf 'Add it to %s (a backup is kept)? [y/N] ' "$SETTINGS"
answer=""
# read fails at the end of input, also after an answer with no newline, and
# keeps what it read; an empty input leaves the answer empty, which is no.
read -r answer || true
echo ""
case "$answer" in
  y | Y | yes | YES | Yes) ;;
  *)
    echo "Claude Code hook: not added. To add it later, run install.sh again, or add this to $SETTINGS:"
    print_hook_entry
    exit 0
    ;;
esac

# shellcheck disable=SC2016 # a jq program: $cmd is a jq variable
write_settings '
  .hooks = (.hooks // {})
  | .hooks.SessionStart = (((.hooks.SessionStart // []) | strip)
      + [{matcher: "clear|resume", hooks: [{type: "command", command: $cmd}]}])
  | .hooks.SessionEnd = (((.hooks.SessionEnd // []) | strip)
      + [{matcher: "clear", hooks: [{type: "command", command: $cmd}]}])
  | .hooks.UserPromptSubmit = (((.hooks.UserPromptSubmit // []) | strip)
      + [{hooks: [{type: "command", command: $cmd}]}])' \
  || { echo "Claude Code hook: not added. Fix $SETTINGS, or add the entry by hand:"; print_hook_entry; exit 0; }
echo "Claude Code hook: added to $SETTINGS. Remove it with install.sh --uninstall-hooks."
