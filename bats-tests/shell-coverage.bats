#!/usr/bin/env bats
#
# Tests for scripts/shell-coverage.sh — the incubated kcov-over-BATS coverage
# helper (tracked by couimet/github-actions#126). Every kcov/bats invocation is
# stubbed and the script runs under a controlled PATH, so its control flow
# (prereq checks, kcov failure, report consolidation, error paths) is exercised
# deterministically without a real kcov run.

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/shell-coverage.sh"

# Write a stub kcov into the given directory. Behavior is selected at runtime
# by KCOV_BEHAVIOR:
#   write-one  — write a single report tree <outdir>/bats.abc/cobertura.xml
#   write-two  — write two report trees (the "found more than one" error)
#   write-none — write no report at all
#   fail       — exit non-zero (simulates a broken kcov run)
# When KCOV_ARGS_FILE is set, the full argument list is recorded there.
kcov_stub() {
  cat > "$1/kcov" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

outdir=""
for a in "$@"; do
  case "$a" in
    -*) ;;
    *) outdir="$a"; break ;;
  esac
done

if [[ -n "${KCOV_ARGS_FILE:-}" ]]; then
  printf '%s\n' "$*" > "$KCOV_ARGS_FILE"
fi

case "${KCOV_BEHAVIOR:-write-one}" in
  write-one)
    mkdir -p "$outdir/bats.abc"
    printf '<coverage/>\n' > "$outdir/bats.abc/cobertura.xml"
    ;;
  write-two)
    mkdir -p "$outdir/bats.a" "$outdir/bats.b"
    printf '<coverage/>\n' > "$outdir/bats.a/cobertura.xml"
    printf '<coverage/>\n' > "$outdir/bats.b/cobertura.xml"
    ;;
  write-none)
    :
    ;;
  fail)
    printf 'kcov exploded\n' >&2
    exit 3
    ;;
esac
STUB
  chmod +x "$1/kcov"
}

# Write a stub bats into the given directory. The script only checks for bats
# presence (the real bats is the program kcov traces, so it is never invoked
# directly) — a trivial executable is enough.
bats_stub() {
  cat > "$1/bats" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$1/bats"
}

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  BIN="$TEST_TEMP_DIR/bin"
  mkdir -p "$BIN"
  kcov_stub "$BIN"
  bats_stub "$BIN"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# ============================================================================
# Prerequisite checks
# ============================================================================

@test "missing kcov → C001, exit 1, names the missing tool (default outdir branch)" {
  # System-only PATH (no BIN, no brew/apt dirs) hides kcov and bats. No outdir
  # argument is passed, exercising the ${1:-<repo>/coverage} default expansion.
  run env PATH="/usr/bin:/bin" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C001"* ]]
  [[ "$output" == *"required tool 'kcov' not found on PATH"* ]]
}

@test "missing bats → C001, exit 1, names the missing tool" {
  kcov_only="$TEST_TEMP_DIR/kcov-only"
  mkdir -p "$kcov_only"
  kcov_stub "$kcov_only"
  run env PATH="$kcov_only:/usr/bin:/bin" "$SCRIPT" "$TEST_TEMP_DIR/out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C001"* ]]
  [[ "$output" == *"required tool 'bats' not found on PATH"* ]]
}

# ============================================================================
# kcov run and report consolidation
# ============================================================================

@test "success: single report consolidated to <outdir>/cobertura.xml and printed" {
  outdir="$TEST_TEMP_DIR/out"
  args_file="$TEST_TEMP_DIR/kcov-args.log"
  mkdir -p "$outdir"
  run env \
    PATH="$BIN:/usr/bin:/bin" \
    KCOV_BEHAVIOR=write-one \
    KCOV_ARGS_FILE="$args_file" \
    "$SCRIPT" "$outdir"
  [ "$status" -eq 0 ]
  # Prints the consolidated report path on stdout.
  [ "$output" = "$outdir/cobertura.xml" ]
  [ -f "$outdir/cobertura.xml" ]
  # The consolidated file is a copy of the produced Cobertura report.
  [[ "$(cat "$outdir/cobertura.xml")" == *"<coverage/>"* ]]
  # kcov was invoked with the include/exclude filters and traced `bats` over
  # the default test directory.
  args="$(cat "$args_file")"
  [[ "$args" == *"--clean"* ]]
  [[ "$args" == *"--include-path="* ]]
  [[ "$args" == *"--exclude-pattern="* ]]
  [[ "$args" == *"$outdir bats bats-tests/"* ]]
}

@test "repeat run with same outdir succeeds and re-consolidates (regression)" {
  # Regression: kcov --clean does not remove the canonical cobertura.xml a
  # previous run copied to <outdir>/, so report discovery used to count it as a
  # second report and exit 2 on the rerun. The canonical copy is dropped before
  # the count, so the second run must pass and rewrite the report.
  outdir="$TEST_TEMP_DIR/out"
  run env PATH="$BIN:/usr/bin:/bin" KCOV_BEHAVIOR=write-one "$SCRIPT" "$outdir"
  [ "$status" -eq 0 ]
  [ "$output" = "$outdir/cobertura.xml" ]
  run env PATH="$BIN:/usr/bin:/bin" KCOV_BEHAVIOR=write-one "$SCRIPT" "$outdir"
  [ "$status" -eq 0 ]
  [ "$output" = "$outdir/cobertura.xml" ]
  [ -f "$outdir/cobertura.xml" ]
  [[ "$(cat "$outdir/cobertura.xml")" == *"<coverage/>"* ]]
}

@test "outdir does not exist → created before the run, success" {
  # Regression: the kcov log redirect happens before kcov runs, so the outdir
  # must be created up front or kcov is never invoked on a fresh checkout.
  outdir="$TEST_TEMP_DIR/does-not-exist"
  run env PATH="$BIN:/usr/bin:/bin" KCOV_BEHAVIOR=write-one "$SCRIPT" "$outdir"
  [ "$status" -eq 0 ]
  [ "$output" = "$outdir/cobertura.xml" ]
  [ -f "$outdir/cobertura.xml" ]
}

@test "outdir not writable → exit 2, error handled without aborting" {
  # When the kcov log cannot be created (unwritable outdir) the redirect fails
  # before kcov runs. The failure branch must tolerate a missing log file
  # (tail ... || true) instead of aborting on the pipeline.
  outdir="$TEST_TEMP_DIR/readonly"
  mkdir -p "$outdir"
  chmod a-w "$outdir"
  run env PATH="$BIN:/usr/bin:/bin" KCOV_BEHAVIOR=write-one "$SCRIPT" "$outdir"
  chmod u+w "$outdir"
  [ "$status" -eq 2 ]
  [[ "$output" == *"C001"* ]]
}

@test "kcov run failure → exit 2, last log lines surfaced" {
  outdir="$TEST_TEMP_DIR/out"
  mkdir -p "$outdir"
  run env PATH="$BIN:/usr/bin:/bin" KCOV_BEHAVIOR=fail "$SCRIPT" "$outdir"
  [ "$status" -eq 2 ]
  [[ "$output" == *"C001"* ]]
  [[ "$output" == *"kcov exploded"* ]]
}

@test "no report produced → C002, exit 2, no consolidated file" {
  outdir="$TEST_TEMP_DIR/out"
  mkdir -p "$outdir"
  run env PATH="$BIN:/usr/bin:/bin" KCOV_BEHAVIOR=write-none "$SCRIPT" "$outdir"
  [ "$status" -eq 2 ]
  [[ "$output" == *"C002"* ]]
  [[ "$output" == *"no cobertura.xml"* ]]
  [ ! -f "$outdir/cobertura.xml" ]
}

@test "more than one report produced → C002, exit 2, never uploads silently" {
  outdir="$TEST_TEMP_DIR/out"
  mkdir -p "$outdir"
  run env PATH="$BIN:/usr/bin:/bin" KCOV_BEHAVIOR=write-two "$SCRIPT" "$outdir"
  [ "$status" -eq 2 ]
  [[ "$output" == *"C002"* ]]
  [[ "$output" == *"expected one cobertura.xml but found 2"* ]]
  [ ! -f "$outdir/cobertura.xml" ]
}
