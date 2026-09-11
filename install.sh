#!/bin/bash
set -euo pipefail

SKILLS_DIR="$HOME/.claude/skills"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)/skills"

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
# is what makes a broken link attributable: only a link pointing under
# REPO_DIR was created from this checkout. A broken link pointing anywhere
# else belongs to something this installer does not manage, so it is left
# alone even though it is equally broken.
pruned=0
for target in "$SKILLS_DIR"/*; do
  [ -L "$target" ] || continue
  [ ! -e "$target" ] || continue
  link_target="$(readlink "$target")"
  if [[ "$link_target" != "$REPO_DIR"/* ]]; then
    continue
  fi
  # The prefix match above is lexical, so a target that escapes through `..`
  # still carries the prefix while resolving outside the checkout. It cannot
  # be canonicalized, because a target that still existed would not be a
  # broken link, so reject the escape instead of resolving it.
  if [[ "$link_target" == *"/../"* || "$link_target" == *"/.." ]]; then
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
