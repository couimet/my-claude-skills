#!/usr/bin/env bash
#
# stamp-skills.sh — Stamps version: field into all skills/*/SKILL.md frontmatters.
#
# Usage: stamp-skills.sh [VERSION] [--dry-run]
#
# Output (one line per skill, in alphabetical order):
#   skills/X/SKILL.md    (no change)              already at target version
#   skills/X/SKILL.md    old_ver → new_ver         updated in-place
#   skills/X/SKILL.md    (new) → new_ver           first stamp
#   WARNING: skills/X/SKILL.md  <reason>           malformed frontmatter, skipped
#
# Summary line:
#   Stamped N file(s), M skipped (already at version), K warning(s)

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: stamp-skills.sh [VERSION] [--dry-run]

  VERSION   Optional CalVer@SHA string (e.g., 2026.02.25@abc1234)
            If omitted, derived from CHANGELOG.md + git HEAD SHA
  --dry-run Preview changes without writing files
  --help    Show this help message
EOF
}

VERSION=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$VERSION" ]]; then
        VERSION="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  CALVER=$(grep -m1 '^## [0-9]' CHANGELOG.md | sed 's/^## //')
  if [[ -z "$CALVER" ]]; then
    echo "Error: No CalVer version found in CHANGELOG.md. Run from the project root or pass VERSION explicitly." >&2
    exit 1
  fi
  SHA=$(git rev-parse --short HEAD)
  VERSION="${CALVER}@${SHA}"
fi

if [[ ! "$VERSION" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?@[0-9a-f]{7,40}$ ]]; then
  echo "Error: VERSION must match CalVer@SHA format (e.g., 2026.02.25.3@abc1234), got: $VERSION" >&2
  exit 1
fi

if [[ ! -d "skills" ]]; then
  echo "Error: skills/ directory not found. Run from the project root." >&2
  exit 1
fi

stamped=0
skipped=0
warnings=0

# Process each SKILL.md in sorted alphabetical order
while IFS= read -r skill_file; do
  result=$(SKILL_FILE="$skill_file" TARGET_VERSION="$VERSION" DRY_RUN="$DRY_RUN" python3 <<'PYEOF'
import os
import re
import sys

file_path = os.environ["SKILL_FILE"]
version   = os.environ["TARGET_VERSION"]
dry_run   = os.environ["DRY_RUN"] == "true"

try:
    with open(file_path) as f:
        content = f.read()
except IOError as e:
    print(f"warning|error reading file: {e}|{file_path}")
    sys.exit(0)

# Parse frontmatter by finding the opening and closing --- lines
lines = content.split("\n")
if not lines or lines[0] != "---":
    print(f"warning|missing opening --- delimiter|{file_path}")
    sys.exit(0)

close_idx = None
for i, line in enumerate(lines[1:], 1):
    if line == "---":
        close_idx = i
        break

if close_idx is None:
    print(f"warning|unclosed frontmatter (no closing ---)|{file_path}")
    sys.exit(0)

frontmatter = "\n".join(lines[1:close_idx])

if not re.search(r"^name:", frontmatter, re.MULTILINE):
    print(f"warning|no name: field in frontmatter|{file_path}")
    sys.exit(0)

# Find existing version field
version_match = re.search(r"^version:\s*(.+)$", frontmatter, re.MULTILINE)
old_version = version_match.group(1).strip() if version_match else None

# No-op: already at target version
if old_version == version:
    print(f"nochange|{version}|{file_path}")
    sys.exit(0)

# Build new frontmatter
if version_match:
    new_frontmatter = re.sub(
        r"^version:.*$", f"version: {version}", frontmatter, flags=re.MULTILINE
    )
    status = "updated"
else:
    # Insert version: on the line immediately after name:
    new_frontmatter = re.sub(
        r"(^name:.*$)",
        r"\1\nversion: " + version,
        frontmatter,
        count=1,
        flags=re.MULTILINE,
    )
    status = "new"
    old_version = ""

rest = "\n".join(lines[close_idx:])
new_content = f"---\n{new_frontmatter}\n{rest}"

if not dry_run:
    try:
        with open(file_path, "w") as f:
            f.write(new_content)
    except OSError as e:
        print(f"warning|error writing file: {e}|{file_path}")
        sys.exit(0)

print(f"{status}|{old_version}|{file_path}")
PYEOF
  )

  IFS='|' read -r status old_ver file <<< "$result"

  case "$status" in
    nochange)
      printf "  %-52s (no change)\n" "$file"
      skipped=$((skipped + 1))
      ;;
    updated)
      printf "  %-52s %s → %s\n" "$file" "$old_ver" "$VERSION"
      stamped=$((stamped + 1))
      ;;
    new)
      printf "  %-52s (new) → %s\n" "$file" "$VERSION"
      stamped=$((stamped + 1))
      ;;
    warning)
      printf "  WARNING: %-44s %s\n" "$file" "$old_ver"
      warnings=$((warnings + 1))
      ;;
    *)
      echo "  ERROR: unexpected result from processor: $result" >&2
      warnings=$((warnings + 1))
      ;;
  esac

done < <(find skills -mindepth 2 -maxdepth 2 -name 'SKILL.md' | sort)

dry_run_label=""
if [[ "$DRY_RUN" == "true" ]]; then
  dry_run_label=" [dry run]"
fi

echo ""
echo "Stamped ${stamped} file(s), ${skipped} skipped (already at version), ${warnings} warning(s)${dry_run_label}"
