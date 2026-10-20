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
  [[ "$output" == *"A001: A | Always emit it"* ]] || false
  [[ "$output" == *"A002: [RECOMMENDED] E | Before Held and after the last answer"* ]] || false
}

@test "extract-answers: counts acknowledged answers and names the unanswered" {
  _wave wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACKNOWLEDGED: 1 of 2"* ]] || false
  [[ "$output" == *"UNANSWERED: A002"* ]] || false
}

@test "extract-answers: omits the UNANSWERED line when every marker is cleared" {
  _wave wave.txt
  sed -i.bak 's/^A002: \[RECOMMENDED\] E$/A002: E/' wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACKNOWLEDGED: 2 of 2"* ]] || false
  [[ "$output" != *"UNANSWERED:"* ]] || false
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
  [[ "$output" != *"answers-ready"* ]] || false
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
  [[ "$output" == *"A001: B | Second option"* ]] || false
  [[ "$output" == *"I switched because the first option assumes the caller holds the questions."* ]] || false
  [[ "$output" == *"A fresh session does not hold them."* ]] || false
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
  [[ "$output" == *"and that line is content."* ]] || false
  [[ "$output" == *"ACKNOWLEDGED: 1 of 1"* ]] || false
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
  [[ "$output" == *"HELD: 2"* ]] || false
  [[ "$output" == *"RETIRED: 1"* ]] || false
}

@test "extract-answers: reports zero held and retired when neither section exists" {
  _wave wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"HELD: 0"* ]] || false
  [[ "$output" == *"RETIRED: 0"* ]] || false
}

# =============================================================
# Error codes
# =============================================================

@test "extract-answers: X001 when the argument count is wrong" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"X001"* ]] || false
}

@test "extract-answers: X002 when the file does not exist" {
  run "$SCRIPT" "$TEST_TEMP_DIR/absent.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"X002"* ]] || false
}

@test "extract-answers: X003 when the file is empty" {
  : > empty.txt
  run "$SCRIPT" empty.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"X003"* ]] || false
}

@test "extract-answers: X004 when an answer has no closer" {
  cat > wave.txt <<'EOF'
# Test Wave

## Q001: Why?

A001: A
EOF
  run "$SCRIPT" wave.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"X004"* ]] || false
  [[ "$output" == *"A001"* ]] || false
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
  [[ "$output" == *"X004"* ]] || false
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
  [[ "$output" == *"X005"* ]] || false
}

@test "extract-answers: X006 when a closer's id does not match its opener" {
  cat > wave.txt <<'EOF'
# Test Wave

A001: A
</A002>
EOF
  run "$SCRIPT" wave.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"X006"* ]] || false
}

@test "extract-answers: X007 when the file holds no answers" {
  printf '# Test Wave\n\nNo answers here.\n' > wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"X007"* ]] || false
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
  [[ "$output" == *"HELD: 2"* ]] || false
  [[ "$output" == *"First held question? Waits on A001."* ]] || false
  [[ "$output" == *"Second held question? Waits on A001."* ]] || false
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
  [[ "$output" == *"RETIRED: 1"* ]] || false
  [[ "$output" == *"A retired question - settled elsewhere."* ]] || false
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
  [[ "$output" == *"HELD: 0"* ]] || false
  [[ "$output" == *"this bullet is part of my answer"* ]] || false
}

# =============================================================
# Terminal wave: retired entries and no answers
# =============================================================

@test "extract-answers: a terminal wave exits 0 and lists every retired entry" {
  cat > wave.txt <<'FIXTURE'
# Wave 3

Retired:

- First retired question? - A004 settled it.
- Second retired question? - A004 settled it.
FIXTURE
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACKNOWLEDGED: 0 of 0"* ]] || false
  [[ "$output" == *"HELD: 0"* ]] || false
  [[ "$output" == *"RETIRED: 2"* ]] || false
  [[ "$output" == *"First retired question? - A004 settled it."* ]] || false
  [[ "$output" == *"Second retired question? - A004 settled it."* ]] || false
}

@test "extract-answers: X007 when the file holds only held entries" {
  printf '# Wave\n\nHeld:\n\n- A held question? Waits on A001.\n' > wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"X007"* ]] || false
}

@test "extract-answers: the terminal-wave example in /question-format parses as written" {
  # The example is the first text fence after the terminal-wave paragraph.
  awk '
    /emits a terminal wave/ { found = 1; next }
    found && /^```text$/ { inside = 1; next }
    inside && /^```$/ { exit }
    inside { print }
  ' "$PROJECT_ROOT/skills/question-format/SKILL.md" > wave.txt
  [ -s wave.txt ]
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACKNOWLEDGED: 0 of 0"* ]] || false
  [[ "$output" == *"RETIRED: 2"* ]] || false
}

# =============================================================
# Text after the letters on the answer line
# =============================================================

# _repro_wave <file> — write a three-question wave: a run of two letters, a
# single letter with a reason after a `;`, and a run of two letters followed by
# text with no `;`, which is ambiguous.
_repro_wave() {
  cat > "$1" <<'FIXTURE'
# Repro wave 1

## Q001: First?

A) Alpha - a
B) Bravo - b
C) Charlie - c

A001: A, C
</A001>

## Q002: Second?

A) Alpha2 - a
B) Bravo2 - b

A002: B; switched because the first option assumes the caller holds the questions.
</A002>

## Q003: Third?

A) Alpha3 - a
B) Bravo3 - b

A003: B, A is wrong because it skips the gate.
</A003>
FIXTURE
}

@test "extract-answers: a run of letters prints each letter with its option text" {
  _repro_wave wave.txt
  sed -i.bak 's/^A003: .*/A003: B/' wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"A001: A, C | Alpha ; Charlie"* ]] || false
}

@test "extract-answers: a reason after a letter and a semicolon prints on an indented line" {
  _repro_wave wave.txt
  sed -i.bak 's/^A003: .*/A003: B/' wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"A002: B | Bravo2"$'\n'"  switched because the first option assumes the caller holds the questions."* ]] || false
}

@test "extract-answers: X008 when a run of letters is followed by text with no semicolon" {
  _repro_wave wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"X008"* ]] || false
  [[ "$output" == *"A003"* ]] || false
}

@test "extract-answers: a marked run of letters counts as unanswered and prints each letter" {
  _repro_wave wave.txt
  sed -i.bak -e 's/^A001: A, C$/A001: [RECOMMENDED] A, C/' -e 's/^A003: .*/A003: B/' wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNANSWERED: A001"* ]] || false
  [[ "$output" == *"A001: [RECOMMENDED] A, C | Alpha ; Charlie"* ]] || false
}

@test "extract-answers: a single letter and a period then text prints the letter and the reason" {
  _repro_wave wave.txt
  sed -i.bak 's/^A003: .*/A003: A. Because it keeps the gate./' wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" != *"X008"* ]] || false
  [[ "$output" == *"A003: A | Alpha3"$'\n'"  Because it keeps the gate."* ]] || false
}

@test "extract-answers: a reason after a semicolon keeps a leading period" {
  _repro_wave wave.txt
  sed -i.bak 's/^A003: .*/A003: A; .env is required/' wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"A003: A | Alpha3"$'\n'"  .env is required"* ]] || false
}

@test "extract-answers: a reason after a letter and a space keeps a leading period" {
  _repro_wave wave.txt
  sed -i.bak 's/^A003: .*/A003: A .env is required/' wave.txt
  run "$SCRIPT" wave.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"A003: A | Alpha3"$'\n'"  .env is required"* ]] || false
}

@test "extract-answers: a multi-line answer prints the rest of the answer line before the body lines" {
  _repro_wave wave.txt
  sed -i.bak -e 's/^A003: .*/A003: B/' -e 's/^A002: B; switched because the first option assumes the caller holds the questions.$/A002: B; switched because of the gate./' wave.txt
  awk '{ print } /^A002: / { print ""; print "A fresh session does not hold them." }' wave.txt > wave2.txt
  run "$SCRIPT" wave2.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"A002: B | Bravo2"$'\n'"  switched because of the gate."$'\n'"  A fresh session does not hold them."* ]] || false
}
