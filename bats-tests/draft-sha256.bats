#!/usr/bin/env bats
#
# Tests for skills/create-jira-issue/draft-sha256.sh — prints the SHA-256 of a
# draft's title and body, the span the ticket-writing plugin approves.
#
# Each expected digest comes from the plugin's draft_hash function
# (ticket-writing, review-ticket-description/scripts/check_ticket.py), run once
# on the same bytes. A digest that changes here means the two sides no longer
# hash the same span, and /create-jira-issue would refuse approved drafts.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/create-jira-issue/draft-sha256.sh"
FIXTURES="$PROJECT_ROOT/bats-tests/fixtures/draft-sha256"

# Digests of the title and body of front-matter.txt, with and without its
# final newline. Several fixtures share this span.
FM_DIGEST="5dda02cafa404e78bea8068e93e623fe2c2e5fa6770ec2b30706ca1b4bd876e8"
FM_NONL_DIGEST="4136350d9259436b8ca47d3ec0b8879f7637d99603cc5476abeec10bd1b53869"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# _crlf <fixture> — write a CRLF copy of a fixture and print its path.
_crlf() {
  local out="$TEST_TEMP_DIR/$1-crlf.txt"
  awk '{ printf "%s\r\n", $0 }' "$FIXTURES/$1.txt" > "$out"
  printf '%s' "$out"
}

# _nonl <fixture> — write a copy of a fixture without its final newline and
# print its path.
_nonl() {
  local out="$TEST_TEMP_DIR/$1-nonl.txt"
  printf '%s' "$(cat "$FIXTURES/$1.txt")" > "$out"
  printf '%s' "$out"
}

@test "draft-sha256: --help exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: draft-sha256.sh"* ]] || false
}

@test "draft-sha256: D001 when given no argument" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"D001"* ]] || false
}

@test "draft-sha256: D002 when the file does not exist" {
  run "$SCRIPT" "$TEST_TEMP_DIR/missing.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"D002"* ]] || false
}

@test "draft-sha256: D003 when no SHA-256 tool is installed" {
  mkdir -p "$TEST_TEMP_DIR/bin"
  ln -s "$(command -v cat)" "$TEST_TEMP_DIR/bin/cat"
  printf 'x\n' > "$TEST_TEMP_DIR/draft.txt"
  PATH="$TEST_TEMP_DIR/bin" run "$BASH" "$SCRIPT" "$TEST_TEMP_DIR/draft.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"D003"* ]] || false
}

@test "draft-sha256: uses sha256sum when shasum is not installed" {
  mkdir -p "$TEST_TEMP_DIR/bin"
  ln -s "$(command -v cat)" "$TEST_TEMP_DIR/bin/cat"
  # The stub records its call, then hashes with the host's own tool.
  local real
  if real="$(command -v shasum)"; then
    real="$real -a 256"
  else
    real="$(command -v sha256sum)"
  fi
  printf '#!/bin/sh\n: > "%s/sha256sum-called"\nexec %s "$@"\n' "$TEST_TEMP_DIR" "$real" > "$TEST_TEMP_DIR/bin/sha256sum"
  chmod +x "$TEST_TEMP_DIR/bin/sha256sum"
  # stdout only: a coverage run writes trace lines to stderr.
  run --separate-stderr env PATH="$TEST_TEMP_DIR/bin" "$BASH" "$SCRIPT" "$FIXTURES/front-matter.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$FM_DIGEST" ]
  [ -f "$TEST_TEMP_DIR/sha256sum-called" ]
}

@test "draft-sha256: skips the front matter and hashes the title and body" {
  run "$SCRIPT" "$FIXTURES/front-matter.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$FM_DIGEST" ]
}

@test "draft-sha256: blank lines before the opening fence do not count" {
  run "$SCRIPT" "$FIXTURES/blank-before-fence.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$FM_DIGEST" ]
}

@test "draft-sha256: a jira-fields map stays inside the front matter" {
  run "$SCRIPT" "$FIXTURES/jira-fields.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "3ab29fac8db7d44e9870846c5d12c135e695be422d1bc32ae2adddbf115ccbaa" ]
}

@test "draft-sha256: leading blank and whitespace-only lines do not count" {
  run "$SCRIPT" "$FIXTURES/leading-blank-lines.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "7ac105fb27e65eef10dbf430e2a8a254feea60b5973fbceace83dfba167b9e56" ]
}

@test "draft-sha256: a block with a prose line is not front matter" {
  run "$SCRIPT" "$FIXTURES/prose-in-block.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "8c4f97e9c5af7962641bfab41f8133524d1056c0f013e6e4e61624de27fdcb65" ]
}

@test "draft-sha256: a file with no front matter hashes from its title" {
  run "$SCRIPT" "$FIXTURES/no-front-matter.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "13147bc988335290fe9b9d650d76f2a527dc61142fe854c508ca07f734e57737" ]
}

@test "draft-sha256: CRLF input hashes like LF input" {
  run "$SCRIPT" "$(_crlf front-matter)"
  [ "$status" -eq 0 ]
  [ "$output" = "$FM_DIGEST" ]
}

@test "draft-sha256: a lone CR counts as a newline" {
  printf 'x\r\ry\r' > "$TEST_TEMP_DIR/lone-cr.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR/lone-cr.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "9e999adc348bc9bf4cd26312129af41b3255e8a06b523e17b2398f808ef52fff" ]
}

@test "draft-sha256: the final newline is part of the hash" {
  run "$SCRIPT" "$(_nonl front-matter)"
  [ "$status" -eq 0 ]
  [ "$output" = "$FM_NONL_DIGEST" ]
}

@test "draft-sha256: a file that holds only front matter hashes the empty text" {
  printf -- '---\na: b\n---' > "$TEST_TEMP_DIR/only-block.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR/only-block.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]
}

@test "draft-sha256: an unclosed block is not front matter" {
  printf -- '---\na: b\n' > "$TEST_TEMP_DIR/unclosed.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR/unclosed.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "61d50b78eb3e801677e44ac203c52235d6113bf8332d632a656c482eb7dbdcb7" ]
}

@test "draft-sha256: a last line of spaces without a newline stays" {
  printf -- '---\na: b\n---\n   ' > "$TEST_TEMP_DIR/trailing-spaces.txt"
  run "$SCRIPT" "$TEST_TEMP_DIR/trailing-spaces.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "0aad7da77d2ed59c396c99a74e49f3a4524dcdbcb5163251b1433d640247aeb4" ]
}
