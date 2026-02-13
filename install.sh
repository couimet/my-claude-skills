#!/bin/bash
set -euo pipefail

SKILLS_DIR="$HOME/.claude/skills"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)/skills"

echo "Installing skills from $REPO_DIR → $SKILLS_DIR"

mkdir -p "$SKILLS_DIR"

installed=0
updated=0
skipped=0

for skill_dir in "$REPO_DIR"/*/; do
  [ -d "$skill_dir" ] || continue
  name=$(basename "$skill_dir")
  target="$SKILLS_DIR/$name"
  source="${skill_dir%/}"

  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  if [ -e "$target" ]; then
    if [ -L "$target" ]; then
      rm "$target"
      updated=$((updated + 1))
    elif [ -f "$target" ]; then
      echo "  WARNING: $target is a regular file (not a symlink). Skipping."
      echo "           Remove it manually if you want this skill managed by the repo."
      skipped=$((skipped + 1))
      continue
    elif [ -d "$target" ]; then
      echo "  WARNING: $target is a real directory (not a symlink). Skipping."
      echo "           Remove it manually if you want this skill managed by the repo."
      skipped=$((skipped + 1))
      continue
    fi
  else
    installed=$((installed + 1))
  fi

  ln -s "$source" "$target"
  echo "  ✓ $name"
done

echo ""
echo "Done: $installed new, $updated updated, $skipped unchanged"
echo "Skills available as /skill-name in all Claude Code projects."
