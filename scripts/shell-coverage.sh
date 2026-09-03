#!/usr/bin/env bash
#
# shell-coverage.sh — Run the BATS suite under kcov and emit a Cobertura report.
#
# INCUBATION COPY — do not grow this script.
#
# This is a repo-local incubation of a shell-coverage capability that belongs
# upstream in couimet/github-actions (the bats-test action + shell-ci-checks
# reusable workflow). It exists here so kcov-on-BATS can be proven in one repo
# before it is promoted to shared CI. Tracked by couimet/github-actions#126,
# created from my-claude-skills issue #177; once that lands, delete this
# script, drop the `coverage` job from ci.yml, and consume the shared coverage
# inputs instead.
#
# Usage: shell-coverage.sh [outdir]
#
#   outdir  Where kcov writes its report tree (default: <repo>/coverage).
#           A single merged report is consolidated to <outdir>/cobertura.xml.
#
# Requires kcov and BATS on PATH. Prints the consolidated report path on
# stdout.
#
# Exit codes:
#   0  — report produced and consolidated to <outdir>/cobertura.xml
#   1  — prerequisite missing (see stderr)
#   2  — no usable Cobertura report produced (see stderr)

set -euo pipefail

readonly ERR_PREREQ="C001"
readonly ERR_NO_REPORT="C002"

# Repo root is the parent of scripts/.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
outdir="${1:-${repo_root}/coverage}"

for tool in kcov bats; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "shell-coverage $ERR_PREREQ error: required tool '$tool' not found on PATH." >&2
    echo "  Install it, e.g. 'brew install kcov bats-core' (macOS) or" >&2
    echo "  'sudo apt-get install kcov bats' (Debian/Ubuntu), then re-run." >&2
    exit 1
  fi
done

cd "$repo_root"

# Trace only shell sources inside this repo. bats-tests/, the report output
# dir, and vendored/generated trees are excluded so the report reflects the
# skills' helper scripts and repo scripts, not the tests themselves.
#
# The kcov stdout/stderr log is redirected into "$outdir/kcov.log", and bash
# sets that redirect up before kcov runs — so the directory must already exist
# or kcov is never invoked (default is <repo>/coverage, absent on a fresh
# checkout). Create it right before the run, after the prereq checks.
mkdir -p "$outdir"

# kcov's bash instrumentation is chatty (trace lines on stderr), so redirect
# its output to a log and surface only the tail on failure; otherwise CI step
# logs would be flooded on every run.
kcov_log="$outdir/kcov.log"
if ! kcov --clean \
  --include-path="$repo_root" \
  --exclude-pattern="bats-tests/,coverage/,.git/,.history/,demo/,node_modules/,\.claude-work/" \
  "$outdir" \
  bats bats-tests/ >"$kcov_log" 2>&1; then
  echo "shell-coverage $ERR_PREREQ error: kcov run failed; last log lines follow" >&2
  tail -n 50 "$kcov_log" >&2 || true
  exit 2
fi

# A previous run's consolidated copy at $outdir/cobertura.xml must not count as
# a fresh report on a repeat run with the same outdir, or the discovery below
# would trip its own "more than one" guard. Drop it so only the report trees
# kcov just wrote are counted; it is regenerated from the nested report.
rm -f "$outdir/cobertura.xml"

# kcov writes one report tree per traced binary (<outdir>/bats.<hash>/).
# Consolidate the produced Cobertura report to a single stable path so the
# upload step does not need to know the hash.
# shellcheck disable=SC2012
report_count="$(find "$outdir" -name cobertura.xml | wc -l | tr -d ' ')"
if [ "$report_count" -eq 0 ]; then
  echo "shell-coverage $ERR_NO_REPORT error: kcov produced no cobertura.xml under $outdir" >&2
  exit 2
fi

# When a future change makes kcov emit more than one report tree, consolidate
# them upstream rather than growing this incubation copy. Fail loudly here so
# a doubled or partial upload never happens silently.
if [ "$report_count" -gt 1 ]; then
  echo "shell-coverage $ERR_NO_REPORT error: expected one cobertura.xml but found $report_count under $outdir" >&2
  echo "  Run: find \"$outdir\" -name cobertura.xml" >&2
  exit 2
fi

report_path="$(find "$outdir" -name cobertura.xml -print -quit)"
cp "$report_path" "$outdir/cobertura.xml"

printf '%s\n' "$outdir/cobertura.xml"
