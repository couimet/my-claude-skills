#!/usr/bin/env bats
#
# Tests for the /answers-ready skill and skills/answers-ready/find-waves.sh,
# which resolves which grill sequence a bare invocation refers to. Resolving
# "the newest questions file" is wrong whenever two grills are open, so most of
# these tests build a questions directory holding more than one sequence.

bats_require_minimum_version 1.7.0

load test_helper

SKILL="$PROJECT_ROOT/skills/answers-ready/SKILL.md"
SCRIPT="$PROJECT_ROOT/skills/answers-ready/find-waves.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  TEST_TEMP_DIR="$(cd "$TEST_TEMP_DIR" && pwd -P)"
  QDIR="$TEST_TEMP_DIR/questions"
  mkdir -p "$QDIR"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# _wave <filename> <answer-line> — write a one-question wave file.
_wave() {
  printf '# Wave\n\n## Q001: Why?\n\nOptions:\nA) A thing - a tradeoff\n\n%s\n</A001>\n' "$2" > "$QDIR/$1"
}

# =============================================================
# Front matter
# =============================================================

@test "answers-ready: file exists" {
  [ -f "$SKILL" ]
}

@test "answers-ready: has name field" {
  grep -q "^name: answers-ready$" "$SKILL"
}

@test "answers-ready: is user-invocable" {
  grep -q "user-invocable: true" "$SKILL"
}

@test "answers-ready: allowed-tools cover both scripts it calls" {
  grep "^allowed-tools:" "$SKILL" | grep -q 'Bash(\*/skills/question/extract-answers.sh \*)'
  grep "^allowed-tools:" "$SKILL" | grep -q 'Bash(\*/skills/answers-ready/find-waves.sh \*)'
}

@test "answers-ready: forbids reading the wave file in full" {
  grep -qi "Never read the wave file" "$SKILL"
}

# This skill owns the whole acknowledgment contract: both file kinds, the
# routing between them, and the finalize procedure its callers delegate. That
# earns more bytes than a skill that only reads one file, and it still reads
# less than the copies its callers used to carry. Keep the ceiling in sight:
# a rule that belongs to a caller does not belong here.
@test "answers-ready: stays small, since a SKILL.md costs context on every invoke" {
  [ "$(wc -c < "$SKILL")" -lt 5600 ]
}

# =============================================================
# Sequence resolution
# =============================================================

@test "find-waves: returns the one sequence whose newest wave is unanswered" {
  _wave "20260917-072350-001-plan-wave-1.txt" "A001: A"
  _wave "20260917-084535-001-plan-wave-2.txt" "A001: [RECOMMENDED] A"
  run "$SCRIPT" "$QDIR"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"plan-wave-2.txt"* ]]
}

@test "find-waves: does not return a sequence whose newest wave is fully answered" {
  _wave "20260917-072350-001-plan-wave-1.txt" "A001: A"
  _wave "20260917-084535-001-plan-wave-2.txt" "A001: B"
  run "$SCRIPT" "$QDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "find-waves: an older sequence wins over a newer file from another sequence" {
  # The regression this script exists for: the newest file belongs to the
  # sequence that emitted last, not the one the user just answered.
  _wave "20260917-084535-001-plan-wave-2.txt" "A001: [RECOMMENDED] A"
  _wave "20260917-092934-001-signalling-wave-2.txt" "A001: E"
  run "$SCRIPT" "$QDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan-wave-2.txt"* ]]
  [[ "$output" != *"signalling"* ]]
}

@test "find-waves: lists every sequence when more than one is unanswered" {
  _wave "20260917-084535-001-plan-wave-2.txt" "A001: [RECOMMENDED] A"
  _wave "20260917-092934-001-signalling-wave-2.txt" "A001: [RECOMMENDED] E"
  run "$SCRIPT" "$QDIR"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
  [[ "$output" == *"plan"* ]]
  [[ "$output" == *"signalling"* ]]
}

@test "find-waves: picks the highest wave number, not the newest timestamp" {
  _wave "20260917-092934-001-plan-wave-1.txt" "A001: [RECOMMENDED] A"
  _wave "20260917-072350-001-plan-wave-2.txt" "A001: B"
  run "$SCRIPT" "$QDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "find-waves: treats a file with no wave suffix as its own sequence" {
  _wave "20260917-072350-001-standalone-topic.txt" "A001: [RECOMMENDED] A"
  run "$SCRIPT" "$QDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"standalone-topic"* ]]
}

@test "find-waves: skips an empty file, which is an unwritten reservation" {
  : > "$QDIR/20260917-093000-001-plan-wave-3.txt"
  _wave "20260917-084535-001-plan-wave-2.txt" "A001: [RECOMMENDED] A"
  run "$SCRIPT" "$QDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan-wave-2.txt"* ]]
  [[ "$output" != *"wave-3"* ]]
}

@test "find-waves: reports the count of answers still marked" {
  printf '# W\n\nA001: [RECOMMENDED] A\n</A001>\nA002: [RECOMMENDED] B\n</A002>\n' \
    > "$QDIR/20260917-084535-001-plan-wave-1.txt"
  run "$SCRIPT" "$QDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\t2' ]]
}

# The marker also appears in prose whenever a wave file discusses the
# convention, and two real, fully answered wave files on issue 259 were
# reported as open for days because of it. Count it only where it opens an
# answer. This mirrors the closer rule in /question-format: a line quoting a
# delimiter while discussing it is content, not a delimiter.
@test "find-waves: the marker in prose is not an unanswered question" {
  printf '# Wave\n\n## Q001: Why?\n\nContext: A002 chose the hard gate, so every `[RECOMMENDED]` marker must be cleared before a consumer proceeds.\n\nOptions:\nA) A thing - a tradeoff\n\nA001: A\n</A001>\n' > "$QDIR/20260101-000000-001-prose-wave-1.txt"
  run "$SCRIPT" "$QDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "find-waves: an indented marker is answer content, not an opener" {
  printf '# Wave\n\n## Q001: Why?\n\nOptions:\nA) A thing - a tradeoff\n\nA001: B\n\n  A001: [RECOMMENDED] A was the suggestion I rejected.\n</A001>\n' > "$QDIR/20260101-000000-001-indented-wave-1.txt"
  run "$SCRIPT" "$QDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "find-waves: prints nothing and succeeds on an empty questions directory" {
  run "$SCRIPT" "$QDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# =============================================================
# Error codes
# =============================================================

@test "find-waves: W001 when given too many arguments" {
  run "$SCRIPT" a b
  [ "$status" -eq 1 ]
  [[ "$output" == *"W001"* ]]
}

@test "find-waves: W002 when the questions directory does not exist" {
  run "$SCRIPT" "$TEST_TEMP_DIR/absent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"W002"* ]]
}

# =============================================================
# W002 names the questions a work folder hides
# =============================================================
#
# A marker or a session override set over existing work retargets this reader
# at once. W002 then said only that the new folder had no questions directory,
# and open waves under the old folder stayed invisible for days.

# _work_repo — a git repository on issues/42 with pinned settings, so the
# resolver and tier-folders.sh answer the same way on every machine.
_work_repo() {
  REPO="$TEST_TEMP_DIR/repo"
  mkdir -p "$REPO"
  cd "$REPO"
  git init -q .
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  git checkout -q -B issues/42
  CFG="$TEST_TEMP_DIR/settings.json"
  printf '%s' '{}' > "$CFG"
  BRANCH_FOLDER="$REPO/.claude-work/issues/42"
  TOPIC="$TEST_TEMP_DIR/topic"
  mkdir -p "$TOPIC"
}

_find_waves_in_repo() {
  run --separate-stderr env -u CLAUDE_CODE_SESSION_ID MY_CLAUDE_SKILLS_CONFIG="$CFG" \
    "$SCRIPT" "$@"
}

@test "find-waves: W002 under a marker names the branch folder that holds questions files" {
  _work_repo
  mkdir -p "$BRANCH_FOLDER/questions"
  printf 'x\n' > "$BRANCH_FOLDER/questions/20260901-100000-001-a-wave-1.txt"
  printf 'x\n' > "$BRANCH_FOLDER/questions/20260901-100000-002-b-wave-1.txt"
  printf '%s\n' "$TOPIC" > "$REPO/CLAUDE_WORK_FOLDER"
  _find_waves_in_repo
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"W002"* ]]
  [[ "$stderr" == *"2 questions files are under $BRANCH_FOLDER/questions, where the branch tier points, but the worktree tier outranks it"* ]]
}

@test "find-waves: W002 under a session override names every outranked tier" {
  _work_repo
  local sid="06cb4128-c112-4696-bddb-3a52d1684a20" sess="$TEST_TEMP_DIR/session-topic"
  mkdir -p "$sess" "$TEST_TEMP_DIR/sessions" "$TOPIC/questions" "$BRANCH_FOLDER/questions"
  printf '{"version":1,"folder":"%s","session_id":"%s"}' "$sess" "$sid" \
    > "$TEST_TEMP_DIR/sessions/$sid.json"
  printf 'x\n' > "$TOPIC/questions/20260901-100000-001-a-wave-1.txt"
  printf 'x\n' > "$BRANCH_FOLDER/questions/20260901-100000-001-b-wave-1.txt"
  printf '%s\n' "$TOPIC" > "$REPO/CLAUDE_WORK_FOLDER"
  run --separate-stderr env CLAUDE_CODE_SESSION_ID="$sid" MY_CLAUDE_SKILLS_CONFIG="$CFG" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"1 questions file is under $TOPIC/questions, where the worktree tier points, but the session tier outranks it"* ]]
  [[ "$stderr" == *"1 questions file is under $BRANCH_FOLDER/questions, where the branch tier points, but the session tier outranks it"* ]]
}

@test "find-waves: W002 with nothing hidden below the winner prints only the error" {
  _work_repo
  printf '%s\n' "$TOPIC" > "$REPO/CLAUDE_WORK_FOLDER"
  mkdir -p "$BRANCH_FOLDER/questions"
  : > "$BRANCH_FOLDER/questions/20260901-100000-001-reserved.txt"
  _find_waves_in_repo
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$stderr" | wc -l | tr -d ' ')" -eq 1 ]
  [[ "$stderr" == *"W002"* ]]
}

@test "find-waves: an explicit directory argument prints only W002" {
  _work_repo
  mkdir -p "$BRANCH_FOLDER/questions"
  printf 'x\n' > "$BRANCH_FOLDER/questions/20260901-100000-001-a-wave-1.txt"
  printf '%s\n' "$TOPIC" > "$REPO/CLAUDE_WORK_FOLDER"
  _find_waves_in_repo "$TOPIC/questions"
  [ "$status" -eq 1 ]
  [[ "$stderr" != *"branch tier"* ]]
  [[ "$stderr" == *"W002"* ]]
}

# =============================================================
# classify-ack.sh: two file kinds reach this skill
# =============================================================
#
# /tackle-pr-comment writes a footer telling the user to send
# `/answers-ready <working document>`, but the extractor reads wave files and
# fails on a working document with "no answers found" — a message about an
# empty wave file, not about the wrong kind of file. The user then has no way
# to report that the decision markers are clear, and the Step 8 gate that
# protects an unread ACCEPT stays shut.

CLASSIFY="$PROJECT_ROOT/skills/answers-ready/classify-ack.sh"

# _doc <filename> <body> — write a /tackle-pr-comment-shaped working document.
_doc() {
  printf '%s\n' "$2" > "$QDIR/$1"
}

@test "classify-ack: a wave file is KIND: wave" {
  _wave "w.txt" "A001: [RECOMMENDED] A"
  run "$CLASSIFY" "$QDIR/w.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"KIND: wave"* ]]
}

@test "classify-ack: a working document is KIND: document" {
  _doc "d.txt" "# PR response

### Feedback A: naming

Decision:  ACCEPT"
  run "$CLASSIFY" "$QDIR/d.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"KIND: document"* ]]
  [[ "$output" == *"UNACKNOWLEDGED: 0"* ]]
}

@test "classify-ack: a standing marker is counted and its item named" {
  _doc "d.txt" "# PR response

### Feedback A: naming

Decision: [RECOMMENDED] ACCEPT

### Feedback B: tests

Decision:  IGNORE"
  run "$CLASSIFY" "$QDIR/d.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DECISIONS: 2"* ]]
  [[ "$output" == *"UNACKNOWLEDGED: 1"* ]]
  [[ "$output" == *"Feedback A - ACCEPT"* ]]
  [[ "$output" != *"Feedback B"* ]]
}

# Same rule as the closer and the wave marker: a token quoted in prose while
# the convention is being discussed is content, not a delimiter.
@test "classify-ack: the marker in prose is not an unacknowledged decision" {
  _doc "d.txt" "# PR response

The user clears [RECOMMENDED] to acknowledge a decision.

### Feedback A: naming

Decision:  ACCEPT"
  run "$CLASSIFY" "$QDIR/d.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNACKNOWLEDGED: 0"* ]]
}

@test "classify-ack: C003 when the file is neither shape" {
  _doc "d.txt" "# Just a note

Nothing to acknowledge here."
  run "$CLASSIFY" "$QDIR/d.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C003"* ]]
}

@test "classify-ack: C001 with no argument, C002 on a missing file" {
  run "$CLASSIFY"
  [ "$status" -eq 2 ]
  [[ "$output" == *"C001"* ]]
  run "$CLASSIFY" "$QDIR/nope.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"C002"* ]]
}

@test "classify-ack: --help exits 0" {
  run "$CLASSIFY" --help
  [ "$status" -eq 0 ]
}

# =============================================================
# The two contracts agree again
# =============================================================

@test "answers-ready: documents both acknowledgment file kinds" {
  grep -q "KIND: wave" "$SKILL"
  grep -q "KIND: document" "$SKILL"
  grep -q "classify-ack.sh" "$SKILL"
}

@test "tackle-pr-comment's footer command is one /answers-ready accepts" {
  grep -q '/answers-ready <absolute path to this file>' "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
  grep -q "classify-ack.sh" "$PROJECT_ROOT/skills/answers-ready/SKILL.md"
}
