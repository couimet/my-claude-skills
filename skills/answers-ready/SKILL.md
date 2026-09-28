---
name: answers-ready
version: 2026.09.21@73231a2
description: Collect a user's acknowledgment from a questions wave file or a working document, without reading either into context. Resolves the wave when no path is given, and owns the procedure for finalizing a pending stub.
argument-hint: '[path-to-wave-file]'
user-invocable: true
allowed-tools: Bash(*/skills/question/extract-answers.sh *), Bash(*/skills/answers-ready/find-waves.sh *), Bash(*/skills/answers-ready/classify-ack.sh *), AskUserQuestion
---

# Answers Ready

The user has finished an acknowledgment file. Collect it and continue the work that was waiting on it.

Two kinds of file carry one. A questions wave file holds `ANNN:` answers, in the format `/question-format` defines. A `/tackle-pr-comment` working document holds `Decision:` lines instead. Both name this skill in their paste-back block, so both arrive here.

**Input:** $ARGUMENTS (optional absolute path to the file)

**Two signals mean the answers are ready, and no others:** the exact `/answers-ready <path>` invocation, and a wave-file path followed by `ready`. The second exists because that is what a user types unprompted, and recognising only the first would fail it silently.

## Step 1: Resolve the file

Remove an exact standalone trailing `ready` token from `$ARGUMENTS` first: it is the second signal above, not part of the path, and the classifier reads it as one. With a path in what remains, use it. With nothing left, run:

```bash
~/.claude/skills/answers-ready/find-waves.sh
```

It prints one `<sequence><TAB><path><TAB><marked count>` line per grill sequence whose newest wave still carries an unanswered question.

- **One line:** use that path.
- **Several lines:** two grills are open. Ask which one with `AskUserQuestion`, listing each sequence name. Never guess.
- **No lines:** every open wave is fully answered. Say so and stop.
- **Error `W002`:** there is no questions directory. Relay any stderr line that names a hidden questions folder, then stop.

## Step 2: Classify, then read the right way

A wave file and a working document need different readers, and passing one to the other's reader fails with a message about the wrong thing. Classify first:

```bash
~/.claude/skills/answers-ready/classify-ack.sh "<path>"
```

- **`KIND: wave`** — continue with Step 3.
- **`KIND: document`** — the same call already printed `DECISIONS:`, `UNACKNOWLEDGED:`, and one line per decision still carrying `[RECOMMENDED]`. Go to Step 3b.
- **Exit 1 (`C003`)** — the path is neither shape. Say so, name both shapes, and stop. Do not guess.

For a wave file, extract the answers:

```bash
~/.claude/skills/question/extract-answers.sh "<path>"
```

Run it once per wave file of the sequence, because a resume needs every wave's answers and not just the newest.

**Never read the wave file.** It runs to thousands of tokens; its answers run to dozens. A script's source never enters context, only its stdout, which is why this filtering is free. The extractor prints each answer beside the text of the option it names, so the answers are actionable without the questions in view, and it prints the `Held:` and `Retired:` lines in full.

## Step 3: Act on a wave file's answers

- `UNANSWERED:` lists answers still carrying `[RECOMMENDED]`. **Stop.** Name those questions and wait. A standing marker never means acceptance.
- `HELD:` above zero means the grill is paused. Resume it with `/g2q` rather than finalizing.
- Otherwise fold the answers into the work that was waiting, using the option text the extractor printed beside each letter.

## Step 3b: Act on a working document's decisions

- **`UNACKNOWLEDGED:` above zero.** **Stop.** Name the feedback items the classifier listed and wait. A standing marker never means the user agreed; it means they have not looked, and an ACCEPT acted on unread is a change nobody approved.
- **`UNACKNOWLEDGED: 0`.** Every decision is acknowledged. Report that, then continue with the work that was waiting: for `/tackle-pr-comment` that is its Step 8, which asks about a commit message and then implements the ACCEPTs.

## Step 4: Finalizing a pending stub

A composite skill that gated its working document on a grill left a pending stub behind: a banner, an outline, and no finalized content. This is the procedure that closes it, and it is the same for every caller. A caller names only what differs: what the document is, which of its sections the answers resolve, and what happens to its pointer.

1. **Check the extractor's output before anything else.** `UNANSWERED:` means stop, name those questions, and wait. `HELD:` above zero means the run is paused: resume grilling by re-running `/g2q`, using the stub's outline plus every answer collected so far as its topic, report the new wave file path, and wait for the user to answer it. The stub stays pending through the pause.
2. **Only when the newest wave file holds nothing** do you fold every answer from every wave into the document and rewrite the stub into the finalized version, resolving each ambiguity per its answer.
3. **Remove the pending-stub banner line.**
4. **Rewrite the same file**, so any pointer that already targets it stays valid.
5. **Report the finalized path and STOP**, matching the caller's no-questions-raised output.

The document is drafted once and finalized once, at the end of the wave sequence. No step before this one writes the finalized version when the gate raised questions.
