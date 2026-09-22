#!/usr/bin/env bats

load test_helper

# =============================================================
# g2q skill: front matter
# =============================================================

@test "g2q: file exists" {
  [ -f "$PROJECT_ROOT/skills/g2q/SKILL.md" ]
}

@test "g2q: has name field" {
  grep -q "^name: g2q$" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

@test "g2q: is user-invocable" {
  grep -q "user-invocable: true" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

@test "g2q: has argument-hint" {
  grep -q "^argument-hint:" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

# target-path.sh folds the gitignore check in itself, so the chain that used to
# require an ensure-gitignore entry here is gone. A caller that writes a working
# file needs the path helper and nothing else.
@test "g2q: allowed-tools cover the /question transitive chain" {
  grep "^allowed-tools:" "$PROJECT_ROOT/skills/g2q/SKILL.md" | grep -q 'Bash(\*/skills/issue-context/target-path.sh \*)'
  ! grep "^allowed-tools:" "$PROJECT_ROOT/skills/g2q/SKILL.md" | grep -q 'ensure-gitignore'
}

# =============================================================
# Composite skills reference g2q at draft time
# =============================================================

@test "start-issue skill: references /g2q" {
  grep -q "/g2q" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "start-issue skill: grill reference appears in Step 4 (after the plan step, before the report step)" {
  STEP4_LINE=$(grep -n "^## Step 4: Create Implementation Plan" "$PROJECT_ROOT/skills/start-issue/SKILL.md" | cut -d: -f1)
  STEP5_LINE=$(grep -n "^## Step 5: Report Status" "$PROJECT_ROOT/skills/start-issue/SKILL.md" | cut -d: -f1)
  GRILL_LINE=$(grep -n "/g2q" "$PROJECT_ROOT/skills/start-issue/SKILL.md" | head -1 | cut -d: -f1)

  [ "$GRILL_LINE" -gt "$STEP4_LINE" ]
  [ "$GRILL_LINE" -lt "$STEP5_LINE" ]
}

@test "start-issue skill: has Step 6 finalize step" {
  grep -q "^## Step 6: Finalize the Plan After Answers" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "tackle-pr-comment skill: references /g2q" {
  grep -q "/g2q" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

@test "tackle-pr-comment skill: grill reference appears in Step 5 (after the working-doc step, before the report step)" {
  STEP5_LINE=$(grep -n "^## Step 5: Create Implementation Working Document" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md" | cut -d: -f1)
  STEP6_LINE=$(grep -n "^## Step 6: Report and Stop" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md" | cut -d: -f1)
  GRILL_LINE=$(grep -n "/g2q" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md" | head -1 | cut -d: -f1)

  [ "$GRILL_LINE" -gt "$STEP5_LINE" ]
  [ "$GRILL_LINE" -lt "$STEP6_LINE" ]
}

@test "tackle-pr-comment skill: has Step 7 finalize step" {
  grep -q "^## Step 7: Finalize the Plan After Answers" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

# =============================================================
# Pending-stub gating contract
# =============================================================

@test "start-issue skill: pending-stub banner names the awaiting-answers contract" {
  grep -q "Production of this plan awaits answers to the questions in" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "tackle-pr-comment skill: pending-stub banner names the awaiting-answers contract" {
  grep -q "Production of this plan awaits answers to the questions in" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

# These four replace assertions about a draft file the stub pointed at. The
# reframe removed the draft, so the stub's outline is now the only written
# record of the reasoning while a grill is open, and a resume re-grills that
# outline rather than re-reading a file.

@test "start-issue skill: the pending stub carries the outline, not a draft pointer" {
  grep -q "the only written record of the reasoning while the grill is open" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
  run bash -c "grep -c 'Draft: <absolute draft path>' '$PROJECT_ROOT/skills/start-issue/SKILL.md' || true"
  [ "$output" -eq 0 ]
}

@test "tackle-pr-comment skill: the pending stub carries the outline, not a draft pointer" {
  grep -q "the only written record of the reasoning while the grill is open" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
  run bash -c "grep -c 'Draft: <absolute draft path>' '$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md' || true"
  [ "$output" -eq 0 ]
}

# The finalize procedure has one home in /answers-ready. Each caller keeps only
# what differs, so the shared phrasing is asserted there and the callers are
# asserted to delegate.
@test "answers-ready: Step 4 re-grills the stub outline plus collected answers" {
  grep -q "using the stub's outline plus every answer collected so far" "$PROJECT_ROOT/skills/answers-ready/SKILL.md"
}

@test "both consumers delegate finalizing to /answers-ready" {
  for f in start-issue tackle-pr-comment; do
    grep -q '`/answers-ready` owns this procedure' "$PROJECT_ROOT/skills/$f/SKILL.md"
    grep -q "stub's outline plus every answer collected so far" "$PROJECT_ROOT/skills/$f/SKILL.md"
  done
}

# =============================================================
# /question <-> /g2q delegation contract
# =============================================================

@test "question skill: argument-hint advertises --format-only" {
  grep -q "argument-hint: '\[--format-only\] <topic>'" "$PROJECT_ROOT/skills/question/SKILL.md"
}

@test "question skill: delegates the challenge to /g2q" {
  grep -q "/g2q" "$PROJECT_ROOT/skills/question/SKILL.md"
}

@test "question skill: no longer owns the single source of trigger truth" {
  run grep -q "single source of trigger truth" "$PROJECT_ROOT/skills/question/SKILL.md"
  [ "$status" -ne 0 ]
}

@test "g2q skill: has the trigger predicate section" {
  grep -q "^## Trigger Predicate" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

@test "start-issue skill: points the trigger predicate at /g2q" {
  grep -q "/g2q.*single source of trigger truth" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "tackle-pr-comment skill: points the trigger predicate at /g2q" {
  grep -q "/g2q.*single source of trigger truth" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

@test "g2q skill: creates the questions file via /question --format-only" {
  grep -q "/question --format-only" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

@test "g2q skill: emits a wave file whenever the run's state changes" {
  grep -q "create a file whenever the run's state changes" "$PROJECT_ROOT/skills/g2q/SKILL.md"
  grep -q "skip this step, create no file" "$PROJECT_ROOT/skills/g2q/SKILL.md"
  grep -q "terminal wave" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

@test "g2q skill: report omits the questions-file path when no questions were raised" {
  grep -q "When no questions were raised, print no path" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

# =============================================================
# Paused-wave contract
# =============================================================

@test "g2q skill: reports a paused run distinctly from a complete one" {
  grep -q "the run is paused" "$PROJECT_ROOT/skills/g2q/SKILL.md"
  grep -q "still lists held questions" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

@test "question skill: relays a paused run distinctly from a complete one" {
  grep -q "the run is paused" "$PROJECT_ROOT/skills/question/SKILL.md"
  grep -q "the run is complete" "$PROJECT_ROOT/skills/question/SKILL.md"
}

@test "both consumers treat a paused grill as pending" {
  for f in start-issue tackle-pr-comment; do
    grep -q "the run is paused" "$PROJECT_ROOT/skills/$f/SKILL.md"
  done
}

@test "answers-ready: a paused grill drains its waves before finalizing" {
  grep -q 're-running `/g2q`' "$PROJECT_ROOT/skills/answers-ready/SKILL.md"
  grep -q "stays pending through the pause" "$PROJECT_ROOT/skills/answers-ready/SKILL.md"
}

@test "question skill: delegation relay states no questions without a filepath" {
  grep -q "No questions raised" "$PROJECT_ROOT/skills/question/SKILL.md"
  grep -q "Nothing else" "$PROJECT_ROOT/skills/question/SKILL.md"
}

# =============================================================
# Answer-region format: the extractor depends on every rule here
# =============================================================

@test "question-format skill: documents the answer closer" {
  grep -q '</ANNN>' "$PROJECT_ROOT/skills/question-format/SKILL.md"
  grep -q "Always write the closer" "$PROJECT_ROOT/skills/question-format/SKILL.md"
}

@test "question-format skill: the closer is required at column zero" {
  grep -qi "column zero" "$PROJECT_ROOT/skills/question-format/SKILL.md"
}

@test "question-format skill: the acknowledgment gate is hard" {
  grep -q "The gate is hard" "$PROJECT_ROOT/skills/question-format/SKILL.md"
  grep -q "standing marker never means acceptance" "$PROJECT_ROOT/skills/question-format/SKILL.md"
}

@test "question-format skill: carries no separate ready-state field" {
  ! grep -qE '^Ready:' "$PROJECT_ROOT/skills/question-format/SKILL.md"
}

@test "question-format skill: documents the paste-back block and its placement" {
  grep -q "answers-ready" "$PROJECT_ROOT/skills/question-format/SKILL.md"
  grep -q "before any \`Held:\` section" "$PROJECT_ROOT/skills/question-format/SKILL.md"
}

@test "question-format skill: forbids reading a questions file to collect answers" {
  grep -q "Never read a questions file in full" "$PROJECT_ROOT/skills/question-format/SKILL.md"
}

@test "g2q skill: emits the closer and the paste-back block" {
  grep -q '</ANNN>' "$PROJECT_ROOT/skills/g2q/SKILL.md"
  grep -q "answers-ready" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

@test "g2q skill: resumes through the extractor rather than reading the wave" {
  grep -q "extract-answers.sh" "$PROJECT_ROOT/skills/g2q/SKILL.md"
  grep -q "Never read a wave file in full" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

# =============================================================
# Consumers collect answers through the extractor
# =============================================================

@test "answers-ready: collects answers through the extractor, once per wave" {
  grep -q "extract-answers.sh" "$PROJECT_ROOT/skills/answers-ready/SKILL.md"
  grep -q "once per wave file of the sequence" "$PROJECT_ROOT/skills/answers-ready/SKILL.md"
  grep -qi "Never read the wave file" "$PROJECT_ROOT/skills/answers-ready/SKILL.md"
}

# The two readiness signals have one home in /answers-ready, which is the skill
# both signals invoke. Asserting them in each consumer was the third copy of a
# spec that only ever had one reader.
@test "answers-ready: recognises exactly two readiness signals" {
  grep -q "Two signals mean the answers are ready, and no others" "$PROJECT_ROOT/skills/answers-ready/SKILL.md"
  grep -q 'followed by `ready`' "$PROJECT_ROOT/skills/answers-ready/SKILL.md"
}

@test "start-issue skill: the commit model moved from the terminal into the note template" {
  # It must be in the 4a note template, and gone from the Step 5 receipt.
  awk '/^### 4a/,/^### 4b/' "$PROJECT_ROOT/skills/start-issue/SKILL.md" | grep -q "Commit model for this plan"
  run bash -c "awk '/^## Step 5: Report Status/,/^## Step 6:/' '$PROJECT_ROOT/skills/start-issue/SKILL.md' | grep -c 'commit-msg'"
  [ "$output" -eq 0 ]
}

@test "tackle-pr-comment skill: decisions carry the acknowledgment marker and a hard gate" {
  grep -q 'Decision: \[RECOMMENDED\]' "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
  grep -q "Check the decision markers first" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

@test "tackle-pr-comment skill: no longer requires a terminal summary of the analysis" {
  ! grep -q "Brief summary of what you found" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

# =============================================================
# The no-draft reframe
# =============================================================

@test "start-issue skill: grills before writing and creates no draft file" {
  grep -q "Grill before writing anything" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
  grep -q "Do not write a draft file first" "$PROJECT_ROOT/skills/start-issue/SKILL.md"
}

@test "tackle-pr-comment skill: grills before writing and creates no draft file" {
  grep -q "Grill before writing anything" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
  grep -q "Do not write a draft file first" "$PROJECT_ROOT/skills/tackle-pr-comment/SKILL.md"
}

@test "neither skill asks target-path.sh for a DRAFT scratchpad" {
  for f in start-issue tackle-pr-comment; do
    run bash -c "grep -c 'DRAFT ' '$PROJECT_ROOT/skills/$f/SKILL.md' || true"
    [ "$output" -eq 0 ]
  done
}

@test "the questions format carries no draft staleness fields" {
  run bash -c "grep -c 'Draft-hash' '$PROJECT_ROOT/skills/question/SKILL.md' || true"
  [ "$output" -eq 0 ]
  run bash -c "grep -c 'DRAFT-HASH' '$PROJECT_ROOT/skills/question/extract-answers.sh' || true"
  [ "$output" -eq 0 ]
}

@test "g2q skill: resume re-grills supplied content, not a draft file" {
  grep -q "Callers no longer write a draft file" "$PROJECT_ROOT/skills/g2q/SKILL.md"
}

@test "run-an-audit doc: no longer points at the deleted audit skill" {
  run bash -c "grep -c 'audit-efficiency/SKILL.md' '$PROJECT_ROOT/docs/run-an-audit.md' || true"
  [ "$output" -eq 0 ]
}
