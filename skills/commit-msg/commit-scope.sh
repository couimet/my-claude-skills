#!/usr/bin/env bash
#
# commit-scope.sh — Print the effective diff of a commit scope, or its scope
# record, for /commit-msg.
#
# Usage:
#   commit-scope.sh [--record] [--path <path>]... [--patch <file>]...
#   commit-scope.sh --help
#
#   --path    A whole path of the scope: a file or a directory, relative to
#             the repository root, or absolute. Repeatable.
#   --patch   A patch file that holds the hunks of the scope in a shared
#             file. Relative to the repository root, or absolute. Repeatable.
#   --record  Print the scope record, not the diff.
#
# A scope needs one flag or more. The script runs from the root of the
# repository of its cwd, so a relative path means the same file for each
# session and for /commit-plan.
#
# The effective diff (stdout, default mode), in this order:
#   1. `git diff HEAD -- <each path>`: the staged and the unstaged changes of
#      the paths, so the commit is HEAD plus the scope.
#   2. Each untracked file under a path (`git ls-files --others
#      --exclude-standard`), as a new-file diff. `git diff HEAD` does not
#      show an untracked file.
#   3. Each patch file, from its first `diff --git` line. The lines above it
#      are comments, as for `git apply`, and do not print.
#
# The scope record (stdout, --record): one line for each flag, in the order
# of the flags, with each path as the caller gave it:
#
#   # scope: path <path>
#   # scope: patch <file>
#
# /commit-msg writes these lines at the top of the message file, and
# /commit-plan reads them. `git commit --cleanup=strip` removes them.
#
# Both modes check the scope first, and print nothing when a check fails:
#   - each path has a change against HEAD, or an untracked file under it;
#   - each patch file exists and holds a `diff --git` line;
#   - no file is in a path and also in a patch file (the `+++ b/` or the
#     `--- a/` file of a patch section is a changed file of a path).
#
# Exit codes:
#   0  — the diff or the record is on stdout
#   1  — error (see stderr): J001 usage, J002 not in a git repository or no
#        HEAD commit, J003 a path with no change or outside the repository,
#        J004 a patch file that is missing or holds no diff, J005 a file in
#        a path and in a patch file

set -euo pipefail

readonly ERR_USAGE="J001"
readonly ERR_REPO="J002"
readonly ERR_PATH="J003"
readonly ERR_PATCH="J004"
readonly ERR_OVERLAP="J005"

usage() {
  cat <<'EOF'
Usage: commit-scope.sh [--record] [--path <path>]... [--patch <file>]...
       commit-scope.sh --help

  --path    A whole path of the scope, repeatable
  --patch   A patch file with the hunks of the scope, repeatable
  --record  Print the scope record (# scope: lines), not the diff
  --help    Show this help message
EOF
}

die() {
  echo "commit-scope $1 error: $2" >&2
  exit 1
}

record=0
kinds=()
values=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --record)
      record=1
      shift
      ;;
    --path | --patch)
      [ "$#" -ge 2 ] && [ -n "$2" ] || die "$ERR_USAGE" "$1 needs a value"
      kinds+=("${1#--}")
      values+=("$2")
      shift 2
      ;;
    *)
      usage >&2
      die "$ERR_USAGE" "unknown argument '$1'"
      ;;
  esac
done
[ "${#kinds[@]}" -gt 0 ] || die "$ERR_USAGE" "a scope needs one --path or --patch flag or more"

top="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "$ERR_REPO" "the cwd is not in a git repository"
cd "$top"
git rev-parse --verify --quiet HEAD >/dev/null \
  || die "$ERR_REPO" "the repository has no HEAD commit, so a scope has no base"

paths=()
patches=()
for i in "${!kinds[@]}"; do
  if [ "${kinds[$i]}" = "path" ]; then
    paths+=("${values[$i]}")
  else
    patches+=("${values[$i]}")
  fi
done

# --- Check each path ---
for p in ${paths[@]+"${paths[@]}"}; do
  rc=0
  git diff HEAD --quiet -- "$p" 2>/dev/null || rc=$?
  [ "$rc" -le 1 ] || die "$ERR_PATH" "path '$p' is outside the repository"
  [ "$rc" -eq 1 ] && continue
  [ -n "$(git ls-files --others --exclude-standard -- "$p")" ] && continue
  die "$ERR_PATH" "path '$p' has no change against HEAD"
done

# --- Check each patch file ---
for f in ${patches[@]+"${patches[@]}"}; do
  [ -f "$f" ] || die "$ERR_PATCH" "patch file '$f' does not exist"
  grep -q '^diff --git ' "$f" || die "$ERR_PATCH" "patch file '$f' holds no 'diff --git' section"
done

# --- Check that no file is in a path and in a patch ---
# The loops read a here-string, not a process substitution: kcov marks the
# `done < <(...)` line of a loop as missed even when the loop runs.
if [ "${#paths[@]}" -gt 0 ] && [ "${#patches[@]}" -gt 0 ]; then
  path_files="$(
    git diff HEAD --name-only -- "${paths[@]}"
    git ls-files --others --exclude-standard --full-name -- "${paths[@]}"
  )"
  for f in "${patches[@]}"; do
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      if printf '%s\n' "$path_files" | grep -Fxq -- "$target"; then
        die "$ERR_OVERLAP" "file '$target' is in a --path and in patch file '$f'"
      fi
    done <<<"$(sed -n -e 's#^+++ b/##p' -e 's#^--- a/##p' "$f" | sort -u)"
  done
fi

# --- Output ---
if [ "$record" -eq 1 ]; then
  for i in "${!kinds[@]}"; do
    printf '# scope: %s %s\n' "${kinds[$i]}" "${values[$i]}"
  done
  exit 0
fi

if [ "${#paths[@]}" -gt 0 ]; then
  git diff HEAD -- "${paths[@]}"
  while IFS= read -r new_file; do
    [ -n "$new_file" ] || continue
    # git diff --no-index exits 1 when the files differ, which is the case
    # for each new file.
    git diff --no-index -- /dev/null "$new_file" || [ "$?" -eq 1 ]
  done <<<"$(git ls-files --others --exclude-standard --full-name -- "${paths[@]}")"
fi
for f in ${patches[@]+"${patches[@]}"}; do
  sed -n '/^diff --git /,$p' "$f"
done
