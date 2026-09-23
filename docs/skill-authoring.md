# Writing a skill

A checklist for adding a skill to this collection, or changing one. ADR 005 carries the reasoning; this is what you do.

The rule behind every item: **a `SKILL.md` tells the model what to do right now.** Its body loads whenever the skill is invoked, and its `description` loads once per session whether or not the skill runs. Anything a running agent does not need belongs somewhere else.

## Before you write

Run `make token-report` and look at where the new skill will sit. If it is a foundation skill several others will pull in, its size is multiplied by how often those run, not by how often anyone types its name.

Decide which kind you are writing:

| Kind       | Front matter            | Cap    | Who loads it                                   |
| ---------- | ----------------------- | ------ | ---------------------------------------------- |
| Ordinary   | (nothing extra)         | 8,000  | The user types `/name`                         |
| Foundation | `user-invocable: false` | 4,000  | Other skills reference it, or it auto-consults |
| Composite  | `skill-kind: composite` | 12,000 | The user types `/name`; it orchestrates others |

Claim `composite` only when the skill genuinely drives five or more others end to end. It is a bigger budget, not a bigger allowance.

## Front matter

```yaml
---
name: my-skill # must match the directory name
version: 2026.09.16@ae50bfe # stamped by CI, never edited by hand
description: One sentence. What it does, not how.
argument-hint: '<thing> [--flag]' # quote it, always
user-invocable: false # omit for a user-facing skill
skill-kind: composite # omit unless it orchestrates
allowed-tools: Read, Write, Bash(*/skills/issue-context/target-path.sh *)
---
```

**Quote any `argument-hint` that starts with `[` or `{`.** Unquoted, YAML reads it as a flow collection, so `argument-hint: [optional: a-path]` parses as a list holding a map rather than as the hint text. `bats-tests/front-matter.bats` fails on this.

**Keep the description short and trigger-bearing.** It is the session floor, paid unconditionally. For a foundation skill that relies on auto-consultation, the trigger phrases are what load it, so those earn their bytes; a routing description for a user-facing skill does not need the same detail.

**Declare every script you call, including transitively.** If your skill references `/prose-style` and `/prose-style` calls a script, your `allowed-tools` needs that script too. `scripts/check-transitive-tools.sh` names every gap, and `make check` runs it.

## Where content goes

| Content                                     | Home                         |
| ------------------------------------------- | ---------------------------- |
| What to run, and what to do with its output | The skill                    |
| Why the design is this way                  | `docs/ADR/`                  |
| What a script does internally               | The script's header comment  |
| A rule more than one skill obeys            | One foundation skill, once   |
| What changed, and when                      | CHANGELOG, PR, `/breadcrumb` |

Two failure modes are worth naming because both read as good documentation:

**History in a header.** "Issue 259 moved X here" answers a question the reader did not ask and goes stale at the next change. Write what the thing does, in the present tense.

**A rule extracted but not deleted.** Moving a rule into a foundation skill and leaving the copy behind costs more than never moving it, because both load. When a rule moves, the copies go. One deliberate exception: the hard-wrap rule is stated inline as well as in `/prose-style`, because its failure rate is high and its inline cost is one sentence.

## Calling a script

State the properties you rely on and nothing else. The caller does not describe the mechanism, so the script stays free to change:

````markdown
Run the path helper:

```bash
~/.claude/skills/issue-context/target-path.sh --type notes --description "$ARGUMENTS"
```

Use the stdout as the full absolute file path. The path is unique and its directory exists, so write the file directly to it. See `/issue-context` for the contract.
````

Never restate a filename format, and never say "timestamped" or "numbered". Those are mechanisms, and ADR 004 bans the words. Use a placeholder such as `<plan-file>.txt` in examples.

**Quote placeholder arguments** in every command you show, fenced or inline: `remove-issue-dir.sh "<folder>" --id "<ID>"`. A configured folder may contain spaces, and the reader substituting the placeholder has no other signal that the result is one argument.

## Reading a file the user edited

Do not read it. Print a script's stdout instead. A questions wave file runs to thousands of tokens while its answers run to dozens, and a script's source never enters context. `extract-answers.sh`, `classify-ack.sh`, `find-waves.sh` and `check-prose.sh` all exist for this reason. If you find yourself writing "re-read the file you just wrote", write a script instead.

## Writing a file

Follow `/prose-style`. One continuous line per paragraph, bare permalinks for code references, full URLs for GitHub references, absolute paths in terminal output. Then run the checker rather than re-reading your own output:

```bash
~/.claude/skills/prose-style/check-prose.sh "<absolute path>"
```

## The terminal is a receipt

Print the path, anything the user must act on, and one `Next:` line. Do not reprint what you just wrote to a file: that pays for the content twice, once to write it and once to say it.

## Before you open the PR

- `make check` passes. It runs the budget, the header check, the transitive-tools gate, lint, and the full bats suite.
- `make token-report` shows your skill under its cap, or you added an allowlist line and said why in the commit.
- Every new script has a header block and a bats file.
- The CHANGELOG has an entry only if an installed skill's behaviour changed. Repo tooling gets none.
- You did not run `make stamp`. CI owns version stamps.
