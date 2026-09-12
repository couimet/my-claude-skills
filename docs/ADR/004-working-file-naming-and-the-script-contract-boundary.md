# ADR 004: Working-file naming and the script-contract boundary

- **Status:** Accepted
- **Date:** 2026-09-10
- **Issue:** <https://github.com/couimet/my-claude-skills/issues/261>

## Context

`.claude-work/` was written by two filename schemes that were never chosen against each other. No decision record exists because no decision was made:

| Date       | PR   | Event                                                                                                                                                                                  |
| ---------- | ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-02-23 | #21  | `/auto-number` added: `NNNN-` prefix, directory scan for the max.                                                                                                                      |
| 2026-03-29 | #118 | `/note` added with `YYYYMMDD-HHMMSS`, described as a lightweight alternative with no foundation-skill dependencies. The date scheme avoided a dependency. Nobody argued it was better. |
| 2026-04-20 | #122 | `target-path.sh` created. Its type allowlist accepted scratchpads, questions, and commit-msgs, with `notes` deliberately absent.                                                       |
| 2026-05-01 | #135 | `notes` added to the allowlist to silence a `T100` error an agent hit. No caller required it.                                                                                          |

Both schemes wrote into the same directories, which produced two defects.

**A date prefix poisoned a directory's sequence permanently.** `auto-number.sh` prefix mode captured the leading digit run before the first hyphen as the high-water mark, and its width guard widened the output to fit rather than rejecting it. One `20260902-131841-third.txt` beside `0001-first.txt` and `0002-second.txt` therefore returned `20260903` instead of `0003`. Every later file in that directory then got an 8-digit pseudo-date: a value that reads as a date, is not one, and drifts by one per file. Renaming the offending file was the only way back.

**The date scheme was specified in prose and never enforced.** `/note` named the format in Markdown and nothing checked it, so filenames missing `-HHMMSS` reached `.claude-work/`. Two same-prefix files in one directory are worse than unordered: two files born 17:59 and 18:24 were both named `20260905-`, which sorted `finish-issue` ahead of `start-issue-plan`, confidently backwards. UTC explains those names. Three of the four affected files were born after 17:00 local in a UTC-7 zone, where a UTC stamp yields the next day's date. The fourth was born at 13:03 local and matches its name. Prose could not prevent that, because nothing sat between the instruction and the filename.

The two defects compounded: a date-only file was both unordered against its same-day siblings and a sequence poisoner for anything numbered beside it.

Hardening the parser was available and rejected. `auto-number.sh` had one consumer left, `target-path.sh`, and `--mode suffix` had none. More code guarding a scheme split that nothing needed is the wrong layer.

## Decision

### Naming

**Stamp every working file `YYYYMMDD-HHMMSS-NNN-<slug>.<ext>` through one helper, and retire `auto-number.sh` along with the `NNNN-` scheme.**

`target-path.sh` is that helper. It already owned path resolution, slug normalization, and directory creation for four of the five types. `/note` therefore routes through it too, and the prose that told the model to run `date` and slugify by hand is deleted. That prose was the unenforced specification, and removing it is the fix rather than a side effect. The `notes` allowlist entry from #135 finally has the caller it never had.

A timestamp is a superset of an ordinal here, and it carries creation time for free. It is not a superset of the ordering, though, which is the correction this section carries after review. A stamp resolves to the second, so two files created inside one second sort by slug and the one created first can sort last. The name therefore keeps a three-digit ordinal between the stamp and the slug, `YYYYMMDD-HHMMSS-NNN-<slug>`, and lexicographic sort equals creation order again. The ordinal is unconditional, because a digit sorts before a letter and an optional one would invert the very pairs it is meant to order.

The ordinal costs a directory scan, which an earlier draft of this ADR claimed to have removed. What made the old scan fragile was reading every sibling: `auto-number.sh` took the leading digit run of any name, so a single date-named file converted a directory's sequence to 8-digit pseudo-dates. This scan is anchored to one second's literal prefix and a fixed-width numeric field, so a malformed sibling is never read at all. That is the property worth keeping, rather than the absence of a scan.

**The stamp is local time.** `date +%Y%m%d-%H%M%S` gives local by default and `/breadcrumb` already stamps local, so a script inherits the right answer by doing nothing special. This is load-bearing rather than incidental: UTC is what produced the wrong dates above, and pinning the choice in a script is the whole point.

**Same-second collisions advance the ordinal, and the path is reserved rather than tested.** A scan could not collide. A stamp can, when two calls land in one second. The ordinal that orders those files is also what resolves them: the script takes the highest ordinal already used for this second, then claims the next one. It claims it with a `noclobber` redirection, which opens with `O_CREAT|O_EXCL`, so the exit status says whether this call created the path or lost the race to a concurrent one, and it advances again when it loses. Testing the path and writing it later left a window where two callers could both be handed the same name; there is now no window, and a dangling symlink at the candidate path is refused too, where a plain `-e` test would have walked straight past it. The alternative, advancing the second until the path is free, names a second the file was not created in. The cost is that a resolved path exists as an empty file before its caller writes, which the contract in `/issue-context` now states.

**No migration.** Existing `NNNN-` files stay. The defect was the scan, not the mixture. With nothing reading neighbours, a numbered file beside a stamped one is untidy but inert. `0001` also sorts before any `2026` prefix, so every newest-file reader keeps working. A rename would have to guess creation time, which is not portable (`stat -f %B` on macOS, `stat -c %W` on Linux, frequently 0). Its mtime fallback names the wrong moment, which reintroduces the wrong-timestamp failure this ADR exists to prevent. Mixed directories drain as `/cleanup-issue` removes finished work items.

Deleting a skill also required the installer to stop leaving debris. `install.sh` now prunes dangling symlinks under `~/.claude/skills/` whose stored target sits under this checkout's `skills/` directory. `readlink` still reports a target after that target is deleted. That is what makes a broken link attributable. A broken link pointing anywhere else is left alone, even though it is equally broken.

### The prose boundary

Moving the naming decision into one script did not, on its own, stop skills from having opinions about it. Twelve prose sites under `skills/` restated the emitted format, none of them consumed it, and swapping `NNNN-` for a timestamp had to be applied to every one. The sweep still missed two statements in the contract doc, both of which described the old arrangement without containing the term being grepped for. That is the characteristic failure of duplicated prose. It is a general problem rather than a naming one, because the same shape recurs wherever a skill documents a script's output.

**A skill that calls a script states the properties it relies on and never the script's output format.** Applied to `target-path.sh`, four properties are the contract and everything else may change without notice:

1. **Absolute.** Safe to print for the user and safe to use from any working directory.
2. **Directory exists and the path is reserved.** The helper creates the directory and reserves the path as an empty file, so the caller writes over its own reservation rather than creating the file.
3. **Unique.** The helper never hands out a path that is already taken, so the only file a caller's write replaces is its own reservation. Two calls never receive the same path, so a caller never checks first.
4. **Lexicographic order equals creation order.** "The newest file matching X" is a maximum rather than a stat call.

The fourth was load-bearing before it was written down. `/rebase-issue` resolves the most recent PR description from filenames, and `/g2q` resolves the newest wave file the same way. Both worked under `NNNN-` because the counter ascended. Both work under a timestamp because the stamp ascends. Neither should have to know which. Stating the property converts an assumption two skills were already making into a guarantee a test can hold.

The format keeps exactly two homes. The first is `target-path.sh` itself. The second is one example in the `/issue-context` contract, marked as an example rather than a specification, so a future editor knows it is safe to let drift. `skills/README.md` is deliberately out of scope, because it is human-facing orientation rather than per-invocation context, so a concrete example there costs nothing at runtime and helps a reader.

**The pattern is not the only leak.** Vocabulary and worked examples carry the format too. A front-matter description promising "timestamped filenames" is a promise about the current scheme, so changing the scheme means editing every skill that made it. A worked example carrying a real generated name is the format restated in another form. Both rot exactly as the pattern does, and both survived the first sweep of this work because the sweep grepped for the pattern rather than for what it means.

Skills therefore say **"a new file"** or **"uniquely named"**, which are properties, and never name the mechanism: not "timestamped", not "numbered", not "auto-numbered". Examples use a placeholder such as `<plan-file>.txt`. The mechanism words are banned rather than merely discouraged, because a word like "timestamped" reads as harmless documentation right up until the scheme changes.

`/breadcrumb` is exempt. It does not call `target-path.sh`, and it stamps the entries inside `breadcrumb.md` itself, so its timestamps are genuinely its own concern.

**The contract does not name its callers either.** A shared doc that lists who calls it rots silently, because whoever changes a caller has no reason to open the contract. Both instances found while writing this ADR had been wrong for some time. The front-matter description listed three callers after a fourth had joined. A History section cited `/auto-number` as a live exemplar after that skill was deleted. `/issue-context` now describes its callers by role, and a test holds that.

The rule is scoped to that one file rather than generalized, because direction is invisible to a grep. `/prose-style` named in a skill body reads identically whether that skill calls prose-style or is called by it, and only the second is rot. Separating them would need a per-skill allowlist of permitted names, which is the same kind of cross-skill detail the rule exists to delete. Two foundation skills, `/file-placement` and `/skill-hooks`, exist precisely to name other skills, so any general form would need them exempt as well.

`bats-tests/script-contract-boundary.bats` enforces this across every consumer. It also asserts that the two permitted homes still carry the format. A later cleanup that deletes the format everywhere therefore fails the suite, instead of leaving the contract undiscoverable.

One consequence of the rule is that `/note` lost its prose guard against deriving its own timestamp. The guard named the concepts the rule removes, and it was never the real barrier. Withholding `Bash(date *)` from the skill's `allowed-tools` is mechanical, and the model cannot argue its way around it. The model can argue its way around prose. The permission assertion stays in `bats-tests/note.bats`.

## Consequences

### Positive

- A malformed sibling cannot affect any other filename. The emitted name is a function of the clock and the description alone.
- The format is enforced where it is produced. A caller cannot get the date wrong, cannot omit the time, and cannot pick UTC by accident, because it never writes a filename.
- Creation time is readable from the name, which the ordinal never carried. `/rebase-issue` finding the most recent PR description and `/g2q` finding the newest wave both become a lexicographic maximum.
- One helper serves all five working-file types, so `/note` stops being the one skill with its own naming rules.
- Tests pin the clock with a `date` stub on `PATH`, the technique `bats-tests/shell-coverage.bats` already uses. No test-only seam entered `target-path.sh`.
- A naming change is now a one-file change plus tests. The twelve consumer restatements are gone, so nothing outside `target-path.sh` has to be found and updated when the format moves again.
- The four contract properties are written down and tested, so `/rebase-issue` and `/g2q` no longer rely on an ordering guarantee nobody stated.

### Negative

- **Timestamps are harder to say aloud than ordinals.** "Scratchpad 3" was easy to reference in conversation. `20260909-101500` is not. In-file identifiers (`Q001`, `A001`, `#S002`) are unaffected, so the cost is confined to filenames, and tab completion covers most of it in practice.
- **Directories with in-flight work show both schemes** until that work item is cleaned up. Accepted in place of a rename that would have to guess creation time.
- **Two calls in the same second with the same slug produce a name that is not purely a timestamp.** The `-2` suffix is a small irregularity in an otherwise uniform scheme, confined to the case that caused it.
- **A reader of a consumer skill can no longer see what its files are called** without opening the contract or the script. Accepted: the reader who needs that is rarer than the editor who has to keep twelve copies true.
- **The illustrative example in the contract doc relies on its marking being respected.** A future editor who treats it as normative recreates a smaller version of the same problem.
- **The installer's prune cannot reach links from a previous checkout path.** Their stored target is not under the current `REPO_DIR`, so they survive. The relink branch added alongside handles the case where such a link belongs to a skill that still exists. A link to a skill that was also removed stays until the user clears it.
