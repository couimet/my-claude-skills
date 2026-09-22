#!/usr/bin/env bats
#
# Tests for skills/question/extract-answers.sh — prints the answers of a
# /question wave file without reading the file into a model's context. The
# script touches no configuration and resolves no paths, so these tests need
# only a temp directory holding the fixture files each one builds.

bats_require_minimum_version 1.7.0

load test_helper

SCRIPT="$PROJECT_ROOT/skills/question/extract-answers.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# _wave <file> — write a two-question wave file with one acknowledged answer
# and one still carrying [RECOMMENDED].
_wave() {
  cat > "$1" <<'EOF'
# Test Wave

## Q001: Should the closer always be written?

Options:
A) Always emit it - one extra line per answer
B) Only for long answers - silent truncation risk

Recommendation: A - optionality loses answers

A001: A
</A001>

---

## Q002: Where does the block sit?

Options:
A) After the Held section - closest to the end
E) Before Held and after the last answer - above the most deletable section

Recommendation: E - survives deletion

A002: [RECOMMENDED] E
</A002>

---

When you have answered every question above, send this to Claude:

/answers-ready <path>

---
EOF
}

# =============================================================
# Happy path
# =============================================================

@test "extract-answers: prints one line per answer with the option text" {
  _wave wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"A001: A | Always emit it"* ]]
  [[ "$output" == *"A002: [RECOMMENDED] E | Before Held and after the last answer"* ]]
}

@test "extract-answers: counts acknowledged answers and names the unanswered" {
  _wave wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACKNOWLEDGED: 1 of 2"* ]]
  [[ "$output" == *"UNANSWERED: A002"* ]]
}

@test "extract-answers: omits the UNANSWERED line when every marker is cleared" {
  _wave wave.txt
  sed -i.bak 's/^A002: \[RECOMMENDED\] E$/A002: E/' wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACKNOWLEDGED: 2 of 2"* ]]
  [[ "$output" != *"UNANSWERED:"* ]]
}

@test "extract-answers: the output is far smaller than the file it reads" {
  _wave wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [ "${#output}" -lt "$(wc -c < wave.txt)" ]
}

@test "extract-answers: does not treat the paste-back block as an answer" {
  _wave wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" != *"answers-ready"* ]]
}

# =============================================================
# Multi-line answers
# =============================================================

@test "extract-answers: prints a multi-line answer whole rather than truncating it" {
  _wave wave.txt
  # Replace the A001 region with a three-paragraph answer.
  cat > wave.txt <<'EOF'
# Test Wave

## Q001: Why?

Options:
A) First option - a tradeoff
B) Second option - another tradeoff

Recommendation: A - reasoning

A001: B

I switched because the first option assumes the caller holds the questions.
A fresh session does not hold them.
</A001>
EOF
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"A001: B | Second option"* ]]
  [[ "$output" == *"I switched because the first option assumes the caller holds the questions."* ]]
  [[ "$output" == *"A fresh session does not hold them."* ]]
}

@test "extract-answers: an indented closer is answer content, not a delimiter" {
  cat > wave.txt <<'EOF'
# Test Wave

## Q001: Why?

Options:
A) First option - a tradeoff

Recommendation: A - reasoning

A001: A

The closer is written like this:
  </A001>
and that line is content.
</A001>
EOF
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"and that line is content."* ]]
  [[ "$output" == *"ACKNOWLEDGED: 1 of 1"* ]]
}

# =============================================================
# Held and retired sections
# =============================================================

@test "extract-answers: counts held and retired entries" {
  _wave wave.txt
  cat >> wave.txt <<'EOF'

Held:

- A held question? Waits on A001.
- Another held question? Waits on A002.

Retired:

- A retired question - settled elsewhere.
EOF
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"HELD: 2"* ]]
  [[ "$output" == *"RETIRED: 1"* ]]
}

@test "extract-answers: reports zero held and retired when neither section exists" {
  _wave wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"HELD: 0"* ]]
  [[ "$output" == *"RETIRED: 0"* ]]
}

# =============================================================
# Error codes
# =============================================================

@test "extract-answers: X001 when the argument count is wrong" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"X001"* ]]
}

@test "extract-answers: X002 when the file does not exist" {
  run "$SCRIPT" "$TEST_TEMP_DIR/absent.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"X002"* ]]
}

@test "extract-answers: X003 when the file is empty" {
  : > empty.txt
  run "$SCRIPT" empty.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"X003"* ]]
}

@test "extract-answers: X004 when an answer has no closer" {
  cat > wave.txt <<'EOF'
# Test Wave

## Q001: Why?

A001: A
EOF
  run "$SCRIPT" wave.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"X004"* ]]
  [[ "$output" == *"A001"* ]]
}

@test "extract-answers: X004 when a second answer opens before the first closes" {
  cat > wave.txt <<'EOF'
# Test Wave

A001: A
A002: B
</A002>
EOF
  run "$SCRIPT" wave.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"X004"* ]]
}

@test "extract-answers: X005 when a closer has no opener" {
  cat > wave.txt <<'EOF'
# Test Wave

A001: A
</A001>
</A002>
EOF
  run "$SCRIPT" wave.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"X005"* ]]
}

@test "extract-answers: X006 when a closer's id does not match its opener" {
  cat > wave.txt <<'EOF'
# Test Wave

A001: A
</A002>
EOF
  run "$SCRIPT" wave.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"X006"* ]]
}

@test "extract-answers: X007 when the file holds no answers" {
  printf '# Test Wave\n\nNo answers here.\n' > wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"X007"* ]]
}

# =============================================================
# Held and retired text, not just counts
# =============================================================

@test "extract-answers: prints the text of each held question" {
  cat > wave.txt <<'FIXTURE'
# Wave

A001: A
</A001>

Held:

- First held question? Waits on A001.
- Second held question? Waits on A001.
FIXTURE
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"HELD: 2"* ]]
  [[ "$output" == *"First held question? Waits on A001."* ]]
  [[ "$output" == *"Second held question? Waits on A001."* ]]
}

@test "extract-answers: prints the text of each retired question" {
  cat > wave.txt <<'FIXTURE'
# Wave

A001: A
</A001>

Retired:

- A retired question - settled elsewhere.
FIXTURE
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"RETIRED: 1"* ]]
  [[ "$output" == *"A retired question - settled elsewhere."* ]]
}

@test "extract-answers: a bullet inside an answer region is answer text, not a held entry" {
  cat > wave.txt <<'FIXTURE'
# Wave

A001: A

- this bullet is part of my answer
</A001>
FIXTURE
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"HELD: 0"* ]]
  [[ "$output" == *"this bullet is part of my answer"* ]]
}
