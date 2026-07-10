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

echo ""
echo "Done: $installed new, $updated updated, $unchanged unchanged, $conflict conflict(s)"
echo "Skills available as /skill-name in all Claude Code projects."
