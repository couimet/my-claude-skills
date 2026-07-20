#!/usr/bin/env bash
#
# apply-stacked-diff.sh — Apply the unique diff of a stacked PR branch onto
# a target ref. Captures only the changes unique to the stacked branch (not
# present on the target), then applies them via git apply --reject. Uses
# per-run unique resource names and cleans up temp resources on all exit paths.
#
# Usage: apply-stacked-diff.sh <target>
#
#   target   The git ref to rebase onto (e.g., issues/200 or origin/main)
#
# Output (stdout):
#   Progress messages; on failure, paths to .rej files and the patch file
#   for manual resolution.
#
# Exit codes:
#   0 — diff applied and staged successfully
#   1 — error (see stderr for the specific error code)
#
# Error codes:
#   A001 — wrong number of arguments
#   A002 — target ref does not exist or is invalid
#   A003 — no diff to apply (branch has no unique changes)
#   A004 — git apply failed (see .rej files and patch file for details)

set -euo pipefail

readonly ERR_ARGS="A001"
readonly ERR_INVALID_TARGET="A002"
readonly ERR_NO_DIFF="A003"
readonly ERR_APPLY="A004"

usage() {
  cat <<'EOF'
Usage: apply-stacked-diff.sh <target>

  target   The git ref to rebase onto (e.g., issues/200 or origin/main)
EOF
}

# --- Argument parsing ---

if [ "$#" -ne 1 ]; then
  echo "apply-stacked-diff $ERR_ARGS error: expected 1 argument, got $#" >&2
  usage >&2
  exit 1
fi

target="$1"

# Verify the target ref exists.
if ! git rev-parse --verify "$target" >/dev/null 2>&1; then
  echo "apply-stacked-diff $ERR_INVALID_TARGET error: target ref '$target' does not exist or is not a valid ref" >&2
  exit 1
fi

# --- Per-run unique resource names ---

temp_branch="rebase-stacked-$$"
patch_file="$(mktemp /tmp/stacked-diff-XXXXXX.patch)"

# --- Cleanup trap ---

# shellcheck disable=SC2317,SC2329 # invoked via trap
cleanup() {
  git branch -D "$temp_branch" 2>/dev/null || true
  [ "${keep_patch_file:-0}" -ne 1 ] && rm -f "$patch_file"
}
trap cleanup EXIT

# --- Save HEAD to temp branch ---

current_head="$(git rev-parse HEAD)"
git branch "$temp_branch" "$current_head"

# --- Capture unique diff ---

git diff "$target".."$temp_branch" > "$patch_file"

# Verify the patch is non-empty.
if [ ! -s "$patch_file" ]; then
  echo "apply-stacked-diff $ERR_NO_DIFF error: no unique changes to apply — diff '$target..$temp_branch' is empty" >&2
  rm -f "$patch_file"
  exit 1
fi

# --- Reset to target ---

git reset --hard "$target"

# --- Apply with --reject ---

# git apply --reject applies clean hunks directly and writes failing hunks
# to .rej files alongside the affected source files.
if git apply --reject "$patch_file"; then
  # Success — stage and clean up the patch file.
  git add -A
  rm -f "$patch_file"
  echo "apply-stacked-diff: unique diff applied and staged successfully (target: $target)"
  exit 0
fi

# --- Failure path ---

keep_patch_file=1
echo "apply-stacked-diff $ERR_APPLY error: git apply --reject failed" >&2
echo "" >&2
echo "Clean hunks were applied. Rejected hunks were written to .rej files:" >&2

# List .rej files for the user.
find . -name '*.rej' -type f 2>/dev/null | while IFS= read -r rej; do
  echo "  $rej" >&2
done

echo "" >&2
echo "To resolve:" >&2
echo "  1. Inspect each .rej file and hand-apply the rejected hunks to the corresponding source file" >&2
echo "  2. Run: git add -A" >&2
echo "  3. Delete the .rej files when done" >&2
echo "" >&2
echo "The full patch is preserved at: $patch_file" >&2

# Keep patch_file on failure for reference. The trap still cleans up
# the temp branch.

exit 1
