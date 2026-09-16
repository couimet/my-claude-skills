#!/usr/bin/env bats
#
# Tests for skills/issue-context/slugify.sh — the one definition of how
# free-form text becomes a slug. The helper is sourced, not executed, so every
# test sources it inside a clean subshell via `bash -c` and asserts on what the
# function prints, the same style bats-tests/issue-settings.bats uses.

load test_helper

SCRIPT="$PROJECT_ROOT/skills/issue-context/slugify.sh"

# Source the helper in a subshell and print the slug for "$2" bounded by "$3".
slugify() {
  run bash -c 'source "$1"; _issue_context_slugify "$2" "${3-}"' _ "$SCRIPT" "$@"
}

# ============================================================================
# The rules target-path.sh has always applied
# ============================================================================

@test "lowercases and hyphenates" {
  slugify "Route Working Files"
  [ "$status" -eq 0 ]
  [ "$output" = "route-working-files" ]
}

@test "collapses runs of non-alphanumerics into one hyphen" {
  slugify "a -- b __ c!!!d"
  [ "$status" -eq 0 ]
  [ "$output" = "a-b-c-d" ]
}

@test "trims leading and trailing separators" {
  slugify "  --hello world--  "
  [ "$status" -eq 0 ]
  [ "$output" = "hello-world" ]
}

@test "digits survive" {
  slugify "PROJ-123 fix"
  [ "$status" -eq 0 ]
  [ "$output" = "proj-123-fix" ]
}

@test "empty input falls back to 'file'" {
  slugify ""
  [ "$status" -eq 0 ]
  [ "$output" = "file" ]
}

@test "input with nothing sluggable falls back to 'file'" {
  slugify "!!! --- ???"
  [ "$status" -eq 0 ]
  [ "$output" = "file" ]
}

@test "non-ASCII input reduces to ASCII rather than passing bytes through" {
  # The rules produce basic ASCII by construction. Multi-byte characters are
  # non-alphanumeric to the sed class, so they become separators.
  slugify "café • naïve"
  [ "$status" -eq 0 ]
  [ "$output" = "caf-na-ve" ]
}

# ============================================================================
# The bound, which only set-work-folder.sh passes
# ============================================================================

@test "no bound leaves a long slug untouched (target-path.sh's case)" {
  local long="aaaaaaaaaabbbbbbbbbbccccccccccddddddddddeeeeeeeeeeffffffffffgggggggggg"
  slugify "$long"
  [ "$status" -eq 0 ]
  [ "$output" = "$long" ]
  [ "${#output}" -eq 70 ]
}

@test "empty bound is the same as no bound" {
  local long="aaaaaaaaaabbbbbbbbbbccccccccccddddddddddeeeeeeeeeeffffffffffgggggggggg"
  slugify "$long" ""
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 70 ]
}

@test "a bound truncates to that many characters" {
  slugify "aaaaaaaaaabbbbbbbbbbcccccccccc" 10
  [ "$status" -eq 0 ]
  [ "$output" = "aaaaaaaaaa" ]
}

@test "a bound that lands on a hyphen trims it rather than ending on one" {
  # "one-two-three" cut at 8 is "one-two-"; the trailing separator goes.
  slugify "one two three" 8
  [ "$status" -eq 0 ]
  [ "$output" = "one-two" ]
}

@test "a bound longer than the slug changes nothing" {
  slugify "short" 60
  [ "$status" -eq 0 ]
  [ "$output" = "short" ]
}

@test "a non-numeric bound is ignored rather than failing" {
  slugify "one two three" "sixty"
  [ "$status" -eq 0 ]
  [ "$output" = "one-two-three" ]
}

@test "the fallback is bounded like any other result" {
  # The fallback is four characters, so a bound below four is the one case
  # where applying the bound first would return more than max-len asked for.
  slugify "!!!" 2
  [ "$status" -eq 0 ]
  [ "$output" = "fi" ]
}

# ============================================================================
# target-path.sh keeps producing what it always did
# ============================================================================

@test "target-path.sh sources the shared helper instead of inlining the rules" {
  local tp="$PROJECT_ROOT/skills/issue-context/target-path.sh"
  grep -q 'source "\$script_dir/slugify.sh"' "$tp"
  grep -q '_issue_context_slugify "\$description"' "$tp"
  # The retired inline pipeline must not linger alongside the call.
  ! grep -q "s/\[\^a-z0-9\]+/-/g" "$tp"
}
