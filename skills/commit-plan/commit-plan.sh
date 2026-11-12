#!/usr/bin/env bash
#
# commit-plan.sh — Print one commit line for each pending /commit-msg message
# of the live sessions in this working tree, in order. It never stages and
# never commits.
#
# Usage:
#   commit-plan.sh [--exclude <path>]...
#   commit-plan.sh --help
#
#   --exclude  A path that no line stages, relative to the repository root,
#              or absolute. Repeatable. A commit-plan-hook gives these.
#
# The sessions. The script reads `claude agents --json` (the live rows) and
# the session files of session-file.sh. A row is in the plan when its cwd is
# in this working tree: `git rev-parse --show-toplevel` from the cwd gives
# the root of this tree, so a nested worktree is out. The folder of a row is
# the one of the newest session file (by written_at) of its sessionId, else of
# its job: a file whose job_session_id, or whose session_id when it has no
# job_session_id, starts with the 8-character job id of the row. A row with
# no session file is listed as `skipped:`, with no line.
#
# The state of a row. The session that runs this script counts as idle: its
# CLAUDE_CODE_SESSION_ID, or the job of $CLAUDE_JOB_DIR/state.json. Each
# other row whose status is not idle is listed as `held: <status>` (busy,
# waiting, or `no status`), because its files can hold a half-done change.
#
# The messages. Each *.txt file in <folder>/commit-msgs/ of an idle session.
# The scope of a message is its leading `# scope: path <path>` and
# `# scope: patch <file>` lines (commit-scope.sh writes them). A relative
# path or patch file is relative to the repository root. A file with no
# scope line is counted on one `unscoped:` line for each folder. The state of
# each scope entry:
#   path   pending when `git diff HEAD` or an untracked file shows a change
#          under it; committed when not.
#   patch  pending when it applies to the tree of HEAD; committed when it
#          applies there in reverse; stale when neither, or when it is
#          missing.
# A message is in the plan when each entry is pending. With each entry
# committed it is skipped with no line. With a stale entry it is listed as
# `held: stale`. With some entries committed and some pending, it is listed
# as `held: partial`, with the committed entries.
#
# The exclusions. An --exclude path drops each path entry at or under it, and
# each patch whose files are all at or under it. Each drop is listed as
# `excluded:`. A message with no entry left gets no line.
#
# The checks, in order. Each one stops the plan with no line:
#   U005  two messages take the same path, or a path of one message holds a
#         file of a patch of another (each name is listed).
#   U007  the index differs from HEAD, so the first commit would also take
#         the staged changes.
#   U006  a line does not apply after the lines before it. The script runs
#         the full plan in a temporary index, made from HEAD, so the real
#         index does not change. The error names the message whose patch
#         fails, and the earlier message that changed the same file.
#
# The order. By the modification time of each message file, oldest first,
# then by path.
#
# Output (stdout):
#   Plan for <root>: <N> commits
#   ! git add -- '<path>'... && git apply --cached '<patch>'... && git commit --cleanup=strip -F '<message>'
#   ...
#   Not in the plan:
#   held: busy <name> (<session id>)
#   ...
# Each path in a line is absolute, so the line runs from any directory of the
# working tree. A line has the `git add` part only when the message has a
# path, and the `git apply --cached` part only when it has a patch. The "Not
# in the plan:" block prints only when it has an item.
#
# Exit codes:
#   0  — the plan is on stdout, possibly with no commit
#   1  — error (see stderr): U001 usage, U002 not in a git repository or no
#        HEAD commit, U003 jq missing, U004 `claude agents --json` failed,
#        U005 two scopes overlap, U006 a line does not apply, U007 staged
#        changes in the index

set -euo pipefail

readonly ERR_USAGE="U001"
readonly ERR_REPO="U002"
readonly ERR_NO_JQ="U003"
readonly ERR_AGENTS="U004"
readonly ERR_OVERLAP="U005"
readonly ERR_APPLY="U006"
readonly ERR_INDEX="U007"

usage() {
  cat <<'EOF'
Usage: commit-plan.sh [--exclude <path>]...
       commit-plan.sh --help

  --exclude  A path that no line stages, repeatable
  --help     Show this help message
EOF
}

die() {
  echo "commit-plan $1 error: $2" >&2
  exit 1
}

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/issue-settings.sh"
# shellcheck disable=SC1091 # sourced sibling; lint-sh runs shellcheck without -x
source "$_self_dir/../issue-context/session-file.sh"

excludes=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --exclude)
      [ "$#" -ge 2 ] && [ -n "$2" ] || die "$ERR_USAGE" "--exclude needs a value"
      excludes+=("$2")
      shift 2
      ;;
    *)
      usage >&2
      die "$ERR_USAGE" "unknown argument '$1'"
      ;;
  esac
done

top="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "$ERR_REPO" "the cwd is not in a git repository"
top="$(cd "$top" && pwd -P)"
cd "$top"
git rev-parse --verify --quiet HEAD >/dev/null \
  || die "$ERR_REPO" "the repository has no HEAD commit"
command -v jq >/dev/null 2>&1 \
  || die "$ERR_NO_JQ" "jq not found; it is required to read the session files and the claude agents list"

if ! live="$(claude agents --json 2>/dev/null)" \
  || ! printf '%s' "$live" | jq -e 'type == "array"' >/dev/null 2>&1; then
  die "$ERR_AGENTS" "claude agents --json failed, so the live sessions are unknown"
fi

owners="$(_issue_context_session_owners)" || owners=""
self_id="${CLAUDE_CODE_SESSION_ID:-}"
self_first=""
_issue_context_job_first_id self_first || self_first=""

notes=()

# rel <path> — print <path> relative to the repository root, with no leading
# ./ and no trailing /. An absolute path outside the root prints as it is.
rel() {
  local p="$1"
  case "$p" in
    "$top") p="." ;;
    "$top"/*) p="${p#"$top"/}" ;;
  esac
  while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
  while [ "${p%/}" != "$p" ] && [ "$p" != "/" ]; do p="${p%/}"; done
  [ -n "$p" ] || p="."
  printf '%s\n' "$p"
}

# abs <path> — print <path> as an absolute path, relative to the root.
abs() {
  local r
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *)
      r="$(rel "$1")"
      if [ "$r" = "." ]; then printf '%s\n' "$top"; else printf '%s/%s\n' "$top" "$r"; fi
      ;;
  esac
}

# under <a> <b> — 0 when the relative path <a> is <b> or is under it.
under() {
  [ "$2" = "." ] || [ "$1" = "$2" ] || [ "${1#"$2"/}" != "$1" ]
}

# quote <text> — print <text> in single quotes for a shell line.
quote() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}

# patch_files <patch> — print the files of a patch, one per line, relative
# to the root.
patch_files() {
  sed -n -e 's#^+++ b/##p' -e 's#^--- a/##p' "$1" | sort -u
}

# folder_of <session id> <job id> — print the folder of the newest session
# file of the session, else of its job. Prints nothing with no file.
folder_of() {
  local sid="$1" job="$2" row f_sid f_first f_written f_folder best_sid="" best_job=""
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    f_sid="${row%%$'\t'*}"
    row="${row#*$'\t'}"
    f_first="${row%%$'\t'*}"
    row="${row#*$'\t'}"
    f_written="${row%%$'\t'*}"
    f_folder="${row#*$'\t'}"
    if [ "$f_sid" = "$sid" ]; then
      [[ -n "$best_sid" && ! "$f_written" > "${best_sid%%$'\t'*}" ]] || best_sid="$f_written"$'\t'"$f_folder"
    elif [ -n "$job" ] && { [ "${f_first:0:8}" = "$job" ] || { [ -z "$f_first" ] && [ "${f_sid:0:8}" = "$job" ]; }; }; then
      [[ -n "$best_job" && ! "$f_written" > "${best_job%%$'\t'*}" ]] || best_job="$f_written"$'\t'"$f_folder"
    fi
  done <<OWNERS
$owners
OWNERS
  if [ -n "$best_sid" ]; then
    printf '%s\n' "${best_sid#*$'\t'}"
  elif [ -n "$best_job" ]; then
    printf '%s\n' "${best_job#*$'\t'}"
  fi
}

# --- The sessions ---
# One row for each live session, its fields split by the unit separator. The
# loops of this script read a here-string, not a process substitution: kcov
# marks the `done < <(...)` line of a loop as missed even when the loop runs.
rows="$(printf '%s' "$live" | jq -r ' # kcov-exclude-line
  # kcov-exclude-start
  .[] | select(type == "object" and (.sessionId | type == "string") and (.cwd | type == "string"))
  | [.sessionId,
     (if (.id | type == "string") and (.id | length) >= 8 then .id[0:8] else "" end),
     (.name // "-" | tostring),
     (if (.status | type == "string") then .status else "no status" end),
     .cwd]
  | map(gsub("[\u001f\n\r]"; " ")) | join("\u001f")
  # kcov-exclude-end
  ')"
folders=()
while IFS=$'\x1f' read -r r_sid r_job r_name r_status r_cwd; do
  [ -n "$r_sid" ] || continue
  r_top="$({ cd "$r_cwd" && cd "$(git rev-parse --show-toplevel)" && pwd -P; } 2>/dev/null)" || continue
  [ "$r_top" = "$top" ] || continue
  is_self=0
  if [ -n "$self_id" ] && [ "$r_sid" = "$self_id" ]; then
    is_self=1
  elif [ -n "$self_first" ] && [ -n "$r_job" ] && [ "$r_job" = "${self_first:0:8}" ]; then
    is_self=1
  fi
  folder="$(folder_of "$r_sid" "$r_job")"
  if [ -z "$folder" ]; then
    notes+=("skipped: $r_name ($r_sid) has no session file, so the plan cannot find its messages")
    continue
  fi
  if [ "$is_self" -eq 0 ] && [ "$r_status" != "idle" ]; then
    notes+=("held: $r_status $r_name ($r_sid)")
    continue
  fi
  seen=0
  for f in ${folders[@]+"${folders[@]}"}; do [ "$f" != "$folder" ] || seen=1; done
  [ "$seen" -eq 1 ] || folders+=("$folder")
done <<<"$rows"

# --- A temporary index from HEAD ---
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
head_index="$tmp_dir/head.index"
GIT_INDEX_FILE="$head_index" git read-tree HEAD

# path_changed <rel path> — 0 when the path has a change against HEAD.
path_changed() {
  local rc=0
  git diff HEAD --quiet -- "$1" 2>/dev/null || rc=$?
  [ "$rc" -eq 1 ] && return 0
  [ -n "$(git ls-files --others --exclude-standard -- "$1" 2>/dev/null)" ]
}

# --- The messages ---
# Parallel arrays, one item for each pending message: bash 3.2 has no
# associative array. m_paths and m_patches hold one entry per line.
plan=()
m_msgs=()
m_paths=()
m_patches=()
for folder in ${folders[@]+"${folders[@]}"}; do
  unscoped=0
  for msg in "$folder"/commit-msgs/*.txt; do
    [ -f "$msg" ] || continue
    entries=()
    while IFS= read -r line; do
      case "$line" in
        "# scope: path "* | "# scope: patch "*) entries+=("${line#\# scope: }") ;;
        *) break ;;
      esac
    done <<<"$(cat "$msg")"
    if [ "${#entries[@]}" -eq 0 ]; then
      unscoped=$((unscoped + 1))
      continue
    fi
    pending=()
    committed=()
    stale=()
    for e in "${entries[@]}"; do
      kind="${e%% *}"
      value="${e#* }"
      if [ "$kind" = "path" ]; then
        if path_changed "$(rel "$value")"; then pending+=("$e"); else committed+=("$e"); fi
      else
        f="$(abs "$value")"
        if [ ! -f "$f" ]; then
          stale+=("$e")
        elif GIT_INDEX_FILE="$head_index" git apply --cached --check "$f" 2>/dev/null; then
          pending+=("$e")
        elif GIT_INDEX_FILE="$head_index" git apply --cached --check -R "$f" 2>/dev/null; then
          committed+=("$e")
        else
          stale+=("$e")
        fi
      fi
    done
    if [ "${#stale[@]}" -gt 0 ]; then
      notes+=("held: stale $msg (a patch is missing, or applies to HEAD neither way: ${stale[*]})")
      continue
    fi
    [ "${#pending[@]}" -gt 0 ] || continue
    if [ "${#committed[@]}" -gt 0 ]; then
      notes+=("held: partial $msg (no change: ${committed[*]})")
      continue
    fi
    paths_of=""
    patches_of=""
    for e in "${pending[@]}"; do
      kind="${e%% *}"
      value="${e#* }"
      dropped=0
      for x in ${excludes[@]+"${excludes[@]}"}; do
        xr="$(rel "$x")"
        if [ "$kind" = "path" ]; then
          under "$(rel "$value")" "$xr" && dropped=1
        else
          all=1
          while IFS= read -r pf; do
            [ -n "$pf" ] || continue
            under "$pf" "$xr" || all=0
          done <<<"$(patch_files "$(abs "$value")")"
          [ "$all" -eq 0 ] || dropped=1
        fi
      done
      if [ "$dropped" -eq 1 ]; then
        notes+=("excluded: $kind $value from $msg")
      elif [ "$kind" = "path" ]; then
        paths_of="$paths_of$(rel "$value")"$'\n'
      else
        patches_of="$patches_of$(abs "$value")"$'\n'
      fi
    done
    if [ -z "$paths_of$patches_of" ]; then
      notes+=("excluded: $msg has no entry left")
      continue
    fi
    plan+=("$(date -r "$msg" +%s)"$'\t'"$msg"$'\t'"${#m_msgs[@]}")
    m_msgs+=("$msg")
    m_paths+=("$paths_of")
    m_patches+=("$patches_of")
  done
  [ "$unscoped" -eq 0 ] || notes+=("unscoped: $unscoped message files with no scope line in $folder/commit-msgs")
done

# ordered: the indexes of the pending messages, in plan order.
ordered=()
if [ "${#plan[@]}" -gt 0 ]; then
  while IFS= read -r row; do
    ordered+=("${row##*$'\t'}")
  done <<<"$(printf '%s\n' "${plan[@]}" | sort -t $'\t' -k1,1n -k2,2)"
fi

# --- U005: two messages take the same path ---
for a in ${ordered[@]+"${ordered[@]}"}; do
  for b in ${ordered[@]+"${ordered[@]}"}; do
    [ "$a" -lt "$b" ] || continue
    while IFS= read -r pa; do
      [ -n "$pa" ] || continue
      while IFS= read -r pb; do
        [ -n "$pb" ] || continue
        if under "$pa" "$pb" || under "$pb" "$pa"; then
          die "$ERR_OVERLAP" "path '$pa' of ${m_msgs[$a]} and path '$pb' of ${m_msgs[$b]} overlap"
        fi
      done <<<"${m_paths[$b]}"
    done <<<"${m_paths[$a]}"
    for pair in "$a $b" "$b $a"; do
      x="${pair% *}"
      y="${pair#* }"
      while IFS= read -r px; do
        [ -n "$px" ] || continue
        while IFS= read -r patch; do
          [ -n "$patch" ] || continue
          while IFS= read -r pf; do
            [ -n "$pf" ] || continue
            if under "$pf" "$px"; then
              die "$ERR_OVERLAP" "path '$px' of ${m_msgs[$x]} holds file '$pf' of a patch of ${m_msgs[$y]}"
            fi
          done <<<"$(patch_files "$patch")"
        done <<<"${m_patches[$y]}"
      done <<<"${m_paths[$x]}"
    done
  done
done

# --- U007: the index must equal HEAD ---
if [ "${#ordered[@]}" -gt 0 ]; then
  git diff --cached --quiet \
    || die "$ERR_INDEX" "the index holds staged changes, so the first commit would take them too; unstage them with 'git restore --staged :/' and run the plan again"
fi

# --- U006: run the plan in a temporary index ---
sim_index="$tmp_dir/plan.index"
cp "$head_index" "$sim_index"
# touched: one "<file><TAB><message>" line for each file that a message
# before changed. The files of a message join it after its own lines, so a
# failed patch never names its own message as the earlier one.
touched=""
for k in ${ordered[@]+"${ordered[@]}"}; do
  msg="${m_msgs[$k]}"
  own=""
  paths=()
  while IFS= read -r p; do [ -z "$p" ] || paths+=("$p"); done <<<"${m_paths[$k]}"
  if [ "${#paths[@]}" -gt 0 ]; then
    GIT_INDEX_FILE="$sim_index" git add -A -- "${paths[@]}" 2>/dev/null \
      || die "$ERR_APPLY" "the paths of $msg do not stage: ${paths[*]}"
  fi
  while IFS= read -r patch; do
    [ -n "$patch" ] || continue
    if ! GIT_INDEX_FILE="$sim_index" git apply --cached "$patch" 2>/dev/null; then
      earlier=""
      while IFS= read -r pf; do
        [ -n "$pf" ] || continue
        hit="$(printf '%s' "$touched" | awk -F '\t' -v f="$pf" '$1 == f { m = $2 } END { print m }')"
        [ -z "$hit" ] || earlier="$hit"
      done <<<"$(patch_files "$patch")"
      if [ -n "$earlier" ]; then
        die "$ERR_APPLY" "patch $patch of $msg does not apply after $earlier, which changes the same file; make one of the two patches again after the other commit"
      fi
      die "$ERR_APPLY" "patch $patch of $msg does not apply after the lines before it"
    fi
    own="$own$(patch_files "$patch")"$'\n'
  done <<<"${m_patches[$k]}"
  for p in ${paths[@]+"${paths[@]}"}; do own="$own$p"$'\n'; done
  while IFS= read -r pf; do
    [ -z "$pf" ] || touched="$touched$pf"$'\t'"$msg"$'\n'
  done <<<"$own"
done

# --- Output ---
count="${#ordered[@]}"
if [ "$count" -eq 1 ]; then
  echo "Plan for $top: 1 commit"
else
  echo "Plan for $top: $count commits"
fi
for k in ${ordered[@]+"${ordered[@]}"}; do
  msg="${m_msgs[$k]}"
  line="!"
  sep=""
  add=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    add="$add $(quote "$(abs "$p")")"
  done <<<"${m_paths[$k]}"
  if [ -n "$add" ]; then
    line="$line git add --$add"
    sep=" &&"
  fi
  while IFS= read -r patch; do
    [ -n "$patch" ] || continue
    line="$line$sep git apply --cached $(quote "$patch")"
    sep=" &&"
  done <<<"${m_patches[$k]}"
  echo "$line$sep git commit --cleanup=strip -F $(quote "$msg")"
done
if [ "${#notes[@]}" -gt 0 ]; then
  echo "Not in the plan:"
  printf '%s\n' "${notes[@]}"
fi
