# ADR 005: A SKILL.md Is a Runtime Instruction File, Not a Design Document

- **Status:** Accepted
- **Date:** 2026-09-21
- **Issue:** <https://github.com/couimet/my-claude-skills/issues/259>

## Context

Every `SKILL.md` body enters the model's context when its skill is invoked, and every `description` enters once per session whether or not the skill runs. Neither cost was measurable, so the collection grew by accretion: each new behaviour added a section to whichever file already existed, and each new decision added the paragraph that justified it.

A measured week of real usage showed where that lands. `issue-context` had reached 16,785 bytes documenting eight scripts, a settings schema, a three-tier override design and a worktree marker convention, and it loaded in every session. About 14,185 of those bytes described machinery a typical caller never invokes. `/g2q` and `/question` each pulled the other in, 24,330 bytes of paired instruction on the most-activated path in the collection, because one told the reader the file format lived in the other. Seven skills described what a script does inside itself. Four rules were written out in more than one place, so an invocation that loaded two of those skills paid for the same instruction twice in one context window.

None of that was a bad decision at the time. Each was the cheapest next step, and the file that already existed was the nearest home. What was missing was a rule saying which home is the right one, and a number saying when a file has outgrown its job.

## Decision

**A `SKILL.md` tells the model what to do right now. Everything else lives somewhere the model does not load on every invocation.**

Four rules follow from that, and a budget enforces them.

### Rationale belongs in an ADR

Prose that answers "why is it built this way" addresses a human changing the code, not an agent running it. `docs/ADR/` is version-controlled, reviewable, and read by exactly that reader. A skill states the rule it enforces and, where a reader would otherwise break it, one clause saying why. The argument goes to the ADR.

### Script behaviour belongs with the script

A skill that calls a script states what it must do with it: what to run, what the stdout means, whether the exit code matters. How the script achieves that belongs in the script's header comment, which sits beside the code and cannot drift from it. This extends the boundary ADR 004 already drew for `target-path.sh` from one script to all of them. `scripts/check-script-headers.sh` holds that every script has a header to put it in.

### A shared rule has exactly one home

Extracting a rule into a foundation skill and leaving the copy behind costs more than never extracting it, because both load. When a rule moves, the copies go. The exception is a rule whose failure rate is high and whose inline cost is a single sentence: the hard-wrap rule is stated inline as well as in `/prose-style`, deliberately.

### A caller states properties, never mechanisms

Already recorded in ADR 004 for filename format. Generalised here: a caller names the property it relies on, so the thing it calls stays free to change. This is what lets a contract split without touching its callers.

### The budget

`scripts/token-budget.sh` measures both costs and `make lint` enforces the caps:

| Tier                                 | Cap    |
| ------------------------------------ | ------ |
| Foundation (`user-invocable: false`) | 4,000  |
| Ordinary                             | 8,000  |
| Composite (`skill-kind: composite`)  | 12,000 |

Three tiers rather than one, because a single number across skills of different kinds produces a long allowlist, and a long allowlist teaches everyone to add a line instead of thinking. A composite skill orchestrates five or more others and is legitimately larger. It declares itself with `skill-kind: composite`, so the claim is written down and reviewable rather than inferred from a reference count that could move for an unrelated reason.

A skill over its cap earns a line in `skills/.budget-allowlist`. That file is a backlog, not configuration: an entry is a debt, it shows up in a diff, and it is deleted when its skill shrinks.

## Consequences

### Positive

- The two costs are measurable, so a claim about token use can be checked rather than asserted. `make token-report` prints both.
- A skill that regrows past its cap fails CI, rather than being discovered a year later by an audit.
- Rationale gains a home that is reviewed and versioned, which is a better home than a runtime file even ignoring cost.
- A contract can split without its callers changing, because callers name properties.

### Negative

- The allowlist starts at thirteen entries. Tiering the caps brought three skills under and one issue's refactors brought three more; the rest are recorded with a reason each. A long allowlist is a weaker signal than a short one, and shrinking it is ongoing work.
- Caps invite gaming. A skill can meet its number by pushing prose into a foundation skill that then loads anyway. The budget measures files, not chains, and a reader still has to judge whether a split was real.
- The 3.8 characters-per-token ratio is an approximation. Byte counts are exact and token counts are indicative.

## Alternatives Considered

### One cap for every skill (rejected)

Simplest to implement and to explain. Rejected because it put fourteen skills over on day one, including every composite skill, which makes the allowlist the normal case rather than the exception.

### Deriving the composite tier from the reference graph (rejected)

A skill naming three or more others could be classified automatically, with no front-matter field to maintain. Rejected because a cap would then move when an unrelated cross-reference was added or removed, which is the kind of surprise a lint must not produce.

### Reporting without enforcing (rejected)

`make token-report` alone, with nothing failing. Rejected because the growth this ADR addresses happened while every byte was visible to anyone who looked. A report nobody is required to act on does not change what gets written.

### Capping the per-invocation chain instead of the file (rejected)

Closer to what actually costs tokens, since a caller pays for everything it pulls in. Rejected because chain membership is inferred from prose references rather than observed, so the check would fail on a reading of the reference graph rather than on a fact.
