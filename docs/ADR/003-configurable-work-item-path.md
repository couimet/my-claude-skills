# ADR 003: Configurable work-item path convention

- **Status:** Accepted
- **Date:** 2026-09-04
- **Issue:** <https://github.com/couimet/my-claude-skills/issues/248>
- **Amended:** 2026-09-08 by <https://github.com/couimet/my-claude-skills/issues/262> (identifier case)

## Context

Work-item identity is a function of the branch name, and the pattern was hardcoded. A branch had to start with `issues/` or the issue-workflow tooling placed every working file at the `.claude-work/` root. That held while the tooling owned branch naming; it broke when something else owned it. A repository whose CI builds a ticket link from the branch name has already spent that freedom, and the user had to choose between a broken link and scattered files.

The convention was also written down twice. `/start-issue` created branches from hardcoded prose, and the path resolver parsed them with hardcoded logic. They agreed only because both happened to say `issues/`.

## Decision

**Make the work-item path convention configurable through `~/.my-claude-skills/settings.json`, read by the shell scripts.** The path is overridable with `MY_CLAUDE_SKILLS_CONFIG`, which must hold a full path. Five keys ship, each with a built-in default:

| Key              | Default            | Purpose                                                                                                                                                                                                                                                                           |
| ---------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `branchPatterns` | ordered list below | Regexes matched against a branch or a PR head. First match wins. Capture group one is the identifier.                                                                                                                                                                             |
| `branchTemplate` | `issues/{id}`      | Builds a branch name from an identifier. A regex cannot be inverted, so reading and writing use separate keys. Paired with `branchPatterns`: a rendered branch must parse back under the configured patterns to the identifier it was built from, or branch creation is rejected. |
| `urlPatterns`    | ordered list below | Regexes matched against a tracker URL. First match wins. Capture group one is the identifier.                                                                                                                                                                                     |
| `segment`        | `issues`           | Directory between the working-directory root and the identifier. Empty omits it.                                                                                                                                                                                                  |
| `identifierCase` | `upper`            | Case a tracker-key-shaped identifier is folded to. `upper`, `lower`, or `preserve`.                                                                                                                                                                                               |

Default `branchPatterns`: `^issues/([0-9]+)[-_]`, `^issues/([0-9]+)$`, `^issues/([A-Za-z][A-Za-z0-9]*-[0-9]+)`, `^issues/(.+)$`, `^([A-Za-z][A-Za-z0-9]*-[0-9]+)`. The list gains a key-shaped entry ahead of the `issues/` catch-all, and a top-level key-shaped entry that gives bare `PROJ-123-*` branches a folder instead of flat placement. Default `urlPatterns`: `/issues/([0-9]+)`, `/browse/([A-Za-z][A-Za-z0-9]+-[0-9]+)`.

### Identifier case (amendment, issue 262)

**Normalise every resolved identifier to one case, and make that case configurable.** Pattern matching alone does not produce a canonical identifier. `branchPatterns` accepted either case and printed the capture verbatim, a bare identifier was printed verbatim, and the original uppercase-only `urlPatterns` Jira entry refused what the other two accepted. One ticket reached two ways therefore produced two identifiers, two `.claude-work/` folders, and two sets of pointer files, silently on a case-insensitive filesystem and unrecoverably on a case-sensitive one.

Folding happens in one place, `_issue_settings_normalize_identifier` in `issue-settings.sh`, and every boundary that emits an identifier goes through it: the shared branch matcher, both paths of `resolve-issue-id.sh`, and the identifier `render-branch-template.sh` interpolates. Applying it at some boundaries and not others would recreate the asymmetry inside the fix. The Jira `urlPatterns` default is relaxed to `/browse/([A-Za-z][A-Za-z0-9]+-[0-9]+)` in the same change, because folding a capture that the pattern never matches does nothing for a lowercase tracker URL.

The fold is guarded by the tracker-key shape `^[A-Za-z][A-Za-z0-9]*-[0-9]+$` rather than applied blanket. `branchPatterns` includes the `^issues/(.+)$` catch-all, so a blanket fold would turn `issues/my-feature` into `MY-FEATURE`, which is worse than the defect. Numeric identifiers carry no case and are unaffected. A free-form slug that happens to take the key shape, `release-2` for instance, is folded; that is accepted collateral and `identifierCase: preserve` is the escape.

The `upper` default is deliberately not backwards compatible. The defect is that resolution was case-preserving, so a `preserve` default would leave it in place for everyone who never reads a changelog, and `urlPatterns` already forced uppercase, which makes `upper` the value that leaves the resolver self-consistent.

The flexibility lives in the shell scripts, which already resolve paths and which the skills already delegate to. Skill prose gains no branching. This honors the token objection that deferred behavior-replacement hooks in ADR 001, and path resolution is where that deferral ends: this ADR supersedes it.

Branch patterns are the whole identity mechanism. There is no declaration file recording the current work item. This deferral is deliberate and its cost is explicit: a branch renamed after work starts orphans its directory, because nothing else ties the folder to the work. Orphan detection in the cleanup skill is the mitigation.

Config loading is fail-open. A missing file, unreadable file, malformed JSON, or invalid regex writes a warning to stderr and falls back to the built-in defaults; a branch matching no pattern gets flat placement, today's behavior. Refusing to resolve a path is worse than resolving it the old way.

URL patterns match on path shape, not hostname, so self-hosted and enterprise installations resolve the same URLs as github.com. The identifier resolver validates that a value is usable as a path segment and a branch name; it does not validate that the value looks like an identifier.

## Consequences

### Positive

- A repository whose CI already owns the branch-name ticket link keeps its naming and gains per-work-item folders instead of scattered files.
- One ordered pattern list serves every repository: patterns that cannot match a repository's branches are skipped, so no per-repository keying is needed.
- Defaults preserve today's behavior for anyone who never configures. The key-shaped entries extend recognition to key identifiers and bare key branches without disturbing the numeric, slug, and `issues/` rows.
- Skills prose stays linear. The shared scripts own the logic, so consumers inherit the mechanism by delegating, with no branching to maintain across the suite.
- Readers follow the writers. Work-item readers such as `/rebase-issue` resolve the `last-finish-issue` pointer, the notes directory, and the base-branch marker from the same settings-aware work-item folder the writers use, so a non-default `segment` applies to every file in the chain rather than only the ones the path resolver writes.
- The config loader is `jq`'s first declared home as a runtime command dependency in the installer and README, closing a gap that had already run through five consumers.

### Negative

- **A branch renamed after work starts orphans its directory.** Nothing records that folder `42` belongs to work item `42`; only the branch name says so. The cleanup skill's orphan detection finds these and offers them for deletion, but between the rename and the cleanup the folder is detached from the work.
- **An omitted `segment` reintroduces the collision the indirection was created to prevent.** With no segment, the work-item glob also matches the four category directories (`notes`, `questions`, `scratchpads`, `commit-msgs`); an exclusion list in the cleanup scripts handles it, and that list is the part that rots when a fifth category appears. Keeping the default avoids this entirely.
- **Five config keys ship; the ones nobody sets are dead weight.** If real use settles on one, the rest are speculative generality and should be removed rather than documented.
- **Config is a per-developer file under `$HOME`, not shared by the repository.** A team that wants one convention must document it; nothing in the repository enforces agreement.
- **Continuous integration hides dependency gaps.** `jq` is present on standard runners, so the suite passes whether or not the declaration exists. Nothing detects the next omission at its source.
- **The `identifierCase` default relocates existing work-item folders.** A folder created under a pre-fold lowercase spelling no longer corresponds to any branch, and the path-bearing pointer files inside it (`active-plan`, `last-finish-issue`) still name the old path. The `base-branch` marker holds a bare git ref and is unaffected. `/cleanup-issue --sweep` surfaces the stranded folders, because the sweep now resolves branches through the same shared matcher rather than its own capture loop, but it offers deletion rather than relocation.
- **A free-form slug shaped like a tracker key is folded.** `issues/release-2` resolves to `RELEASE-2`. The shape guard cannot tell that slug apart from a tracker key, and `identifierCase: preserve` is the only escape.

## Alternatives Considered

### Behavior-replacement hooks (superseded by this ADR)

ADR 001 deferred behavior replacement, allowing it later at per-decision yield points rather than as a blanket mechanism. Path resolution is exactly such a yield point, and this issue materialized it. The question was whether to honor the deferral by introducing a hook skill at each skill's path-resolution step. Hooks are add-requirements-only and one per parent; making each of the delegating skills branch on hook existence would burn tokens across the suite for a feature few use. A settings file read by one shared, sourced loader is a single yield point implemented once and honored automatically by every consumer. This ADR supersedes ADR 001's deferral for path resolution; ADR 001's file stands as historical record.

### Per-repository configuration (deferred)

Settings keyed by repository would let each repo declare its own convention in-tree. Rejected as a non-goal for this change: an ordered, skip-unmatched pattern list removes the need, and the file is a per-developer convention across all the repositories the global skills run in. Per-repository overrides stay available later, keyed on the remote URL rather than a filesystem path, because a path differs per worktree and a remote does not.

### Case-insensitive folder reuse in the path resolver (rejected, issue 262)

`get-issue-folder-path.sh` could probe for an existing folder under either case and reuse whichever it found. This turns a pure string function into one that reads the filesystem, and it does nothing for the case that was actually observed, where the stale path lived inside a pointer file rather than a directory name.

### Documentation plus a `branchPatterns` override (rejected, issue 262)

Telling users to spell identifiers consistently and to override `branchPatterns` if they want enforcement does not work: `_issue_settings_read_patterns` replaces the whole list rather than appending to it, so an uppercase-only override silently drops the numeric GitHub rows and the `^issues/(.+)$` catch-all unless they are re-listed. Re-list the catch-all and a lowercase branch matches it again and still yields a lowercase identifier, so the override achieves nothing. Omit it and every non-tracker branch loses its folder.

### A stderr warning on a mixed-case branch (rejected, issue 262)

`branch-issue-id.sh` could warn when a branch resolves to a non-canonical identifier. Every caller treats that script as silent-or-exit-1, so the warning becomes noise each of them has to swallow, and it diagnoses the problem without fixing it.

### Hostname-based URL matching (rejected)

Sniffing for a vendor name in the URL host fails on self-hosted and enterprise installations, where the host differs but the path shape does not. URL patterns therefore match on path shape only.

### Refusing to resolve on config error (rejected)

A malformed config could stop path resolution and surface the error. Worse than resolving the old way: the skills' value is that work proceeds, so a config typo should degrade to the default convention rather than halt the workflow.
