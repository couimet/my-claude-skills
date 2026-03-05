# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to this project will be documented in this file.

This project uses [Calendar Versioning](https://calver.org/) with the format `YYYY.0M.0D` (e.g., `2026.02.24`). When multiple versions land on the same day, a micro suffix is appended: `2026.02.24.2`, `2026.02.24.3`, etc.

Entries are organized using [Keep a Changelog](https://keepachangelog.com/) categories: **Added**, **Changed**, **Fixed**, **Removed**. Not every release uses every category — include only the ones that apply.

Contributors are encouraged to add a changelog entry with their PR, but it's not required. CI will nudge you with a non-blocking reminder if CHANGELOG.md wasn't modified.

## 2026.03.05

### Changed

- `auto-number`: improved E002 error message when `prefix` or `suffix` is passed as a positional argument; message now includes a did-you-mean hint (`--mode prefix`/`--mode suffix`) and notes that prefix is the default so `--mode` can be omitted entirely ([issues/64](https://github.com/couimet/my-claude-skills/issues/64))
- `auto-number` SKILL.md: added "Common Mistakes" section with WRONG vs RIGHT examples to prevent Claude from passing `prefix`/`suffix` positionally; added explicit note that prefix is the default and `--mode` should be omitted for prefix mode ([issues/64](https://github.com/couimet/my-claude-skills/issues/64))

## 2026.03.04

### Changed

- `/tackle-scratchpad-block` — replaces the single-step shortcut (step-count proxy) with an explicit `"finish_issue_on_complete"` metadata check: `/finish-issue` is now invoked only when all steps are `"done"` AND the top-level `"finish_issue_on_complete": true` field is present in the JSON block; absent or `false` always produces a `/commit-msg` file regardless of step count, preventing premature `/finish-issue` invocations from CI fix scratchpads and `/tackle-pr-comment` scratchpads ([issues/62](https://github.com/couimet/my-claude-skills/issues/62))
- `/start-issue` — adds `"finish_issue_on_complete": true` to the generated JSON block in the implementation plan template, opting the primary issue deliverable into the automatic `/finish-issue` flow ([issues/62](https://github.com/couimet/my-claude-skills/issues/62))
- `/start-side-quest` — replaces the freeform `## Changes` numbered list with a JSON steps block carrying `"finish_issue_on_complete": true`, making side-quest scratchpads consistent with `/start-issue` and enabling `/tackle-scratchpad-block` step tracking ([issues/62](https://github.com/couimet/my-claude-skills/issues/62))
- `/scratchpad` — documents `"finish_issue_on_complete"` in the JSON schema example (default `false`) and Field Reference, with a new "Top-level fields" / "Step-level fields" split for clarity ([issues/62](https://github.com/couimet/my-claude-skills/issues/62))

## 2026.03.03

### Fixed

- `/create-github-issue` — Step 7 sub-issue linking no longer fails in zsh due to `!` being stripped from GraphQL type annotations (`String!`, `Int!`, `ID!`) by history expansion inside `$()` command substitutions; the node-ID query is now written to `/tmp/gql-nodes.json` via a `<<'GRAPHQL'` heredoc and read with `--input`, and the mutation file is built with `jq -n --arg` and read with `--input` ([issues/56](https://github.com/couimet/my-claude-skills/issues/56))

## 2026.03.02.1

### Changed

- `/tackle-scratchpad-block` — single-step shortcut: when the scratchpad JSON block contains exactly one step, `/finish-issue` is invoked directly after the step completes instead of creating a `/commit-msg` file; multi-step behavior is unchanged ([issues/57](https://github.com/couimet/my-claude-skills/issues/57))

## 2026.03.02

### Added

- `ensure-gitignore` skill — shell script that checks/appends the `.claude-work/` sentinel to `.gitignore` in one Bash call; replaces the previous read-check-append instructions in `/issue-context` that loaded file contents into Claude's context on every foundation skill invocation ([issues/43](https://github.com/couimet/my-claude-skills/issues/43))
- `audit-efficiency` skill — user-invocable; scans any project's `skills/` directory for token-consumption inefficiencies: shell-script candidates (read-check-append patterns, pure computation, existence checks), step sequence parallelization opportunities, and cross-reference loading overhead; outputs a structured HIGH/MEDIUM/LOW impact report ([issues/43](https://github.com/couimet/my-claude-skills/issues/43))

### Changed

- `/issue-context` — `## Ensure .gitignore` section now delegates to `skills/ensure-gitignore/ensure-gitignore.sh` instead of instructing Claude to read the file manually; consistent with the script-backed skill pattern established by `/auto-number` ([issues/43](https://github.com/couimet/my-claude-skills/issues/43))

## 2026.03.01.1

### Added

- `CLAUDE.md` — project-level guidance for AI agents covering development commands, skills architecture (SKILL.md front matter, invocable vs foundation skills, `/skill-name` cross-reference syntax), the issue workflow chain, working files policy, CHANGELOG conventions, and prose formatting rules ([issues/42](https://github.com/couimet/my-claude-skills/issues/42))

## 2026.03.01

### Changed

- All prose-generating skills — removed the `/prose-style` sub-skill reference pattern; each skill now embeds the no-wrap rule directly as an explicit inline instruction ("Never hard-wrap prose output — each paragraph is one continuous line; line breaks for structure only."); the `breadcrumb` skill's generated `.md` file additionally starts with `<!-- markdownlint-disable MD013 -->` to signal intent to markdown-aware tools ([issues/51](https://github.com/couimet/my-claude-skills/issues/51))

### Removed

- `prose-style` skill — deleted; its rules are now embedded directly in each skill that generates prose content rather than maintained as a separately referenced skill

## 2026.02.28

### Fixed

- `/create-github-issue` — Step 7 sub-issue linking no longer requires manual transcription of opaque base64 node IDs; a single shell script now captures IDs into variables via `jq` and passes them programmatically to the mutation, eliminating the copy-paste error mode that caused `NOT_FOUND` failures ([issues/52](https://github.com/couimet/my-claude-skills/issues/52))

## 2026.02.27

### Changed

- `/finish-issue` — extended to support `side-quest/*` branches in addition to `issues/*`; detects branch mode in Step 1, reads breadcrumbs from `.claude-work/breadcrumb-<slug>.md` in side-quest mode, writes PR description to flat `.claude-work/scratchpads/` in side-quest mode; `start-side-quest` Step 5 now references `/finish-issue` for wrap-up ([issues/39](https://github.com/couimet/my-claude-skills/issues/39))

## 2026.02.26.5

### Changed

- `/scratchpad` — `done_when` field description updated from "Optional" to "Recommended for implementation plans"; clarifies when to omit and explicitly notes its role in helping `/tackle-scratchpad-block` confirm step completion ([issues/38](https://github.com/couimet/my-claude-skills/issues/38))

## 2026.02.26.4

### Added

- `/start-issue` — Step 6 report now includes a "Next" line pointing to `/tackle-scratchpad-block` with a bare-path example (auto-selects first pending, unblocked step), bridging the gap between planning and execution ([issues/37](https://github.com/couimet/my-claude-skills/issues/37))

## 2026.02.26.3

### Added

- `/finish-issue` — added scratchpad step-status check as the first item in Pre-PR Verification; warns on pending or in-progress steps and asks for confirmation before proceeding to format, tests, and PR description generation ([issues/36](https://github.com/couimet/my-claude-skills/issues/36))

## 2026.02.26.2

### Added

- `/tackle-scratchpad-block` — added step-ID targeting forms (`#S00N` and space-separated) and bare-path targeting for pending/unblocked steps (auto-select when unique, otherwise list candidates); line-range form (`#L`) unchanged ([issues/33](https://github.com/couimet/my-claude-skills/issues/33))

## 2026.02.26

### Added

- `README` See It In Action — added `/create-github-issue` to the Mermaid lifecycle diagram and as new section 6, explaining when to use it for filing follow-up issues discovered during implementation ([issues/19](https://github.com/couimet/my-claude-skills/issues/19))

## 2026.02.25.3

### Added

- `scripts/stamp-skills.sh` — stamps a `version: CALVER@SHA` field into every `skills/*/SKILL.md` frontmatter; supports `--dry-run`, rich per-file output (`old → new`, `(no change)`, `(new)`), and warn-and-skip for malformed frontmatter ([issues/26](https://github.com/couimet/my-claude-skills/issues/26))
- `.github/workflows/stamp-skills.yml` — CI workflow that runs the stamp script on every push to main and commits back with `[skip ci]`; no-op if all skills already carry the target version ([issues/26](https://github.com/couimet/my-claude-skills/issues/26))
- `Makefile` — `make stamp` target for local invocation with the same CalVer@SHA derivation used by CI ([issues/26](https://github.com/couimet/my-claude-skills/issues/26))

## 2026.02.25.2

### Added

- `.github/workflows/markdownlint.yml` — standalone CI workflow that gates PRs on Markdown formatting ([issues/30](https://github.com/couimet/my-claude-skills/issues/30))
- `setup.sh` — installs `markdownlint-cli2` via Homebrew for local validation ([issues/30](https://github.com/couimet/my-claude-skills/issues/30))
- `Makefile` — `make lint` and `make test` targets as canonical local entry points ([issues/30](https://github.com/couimet/my-claude-skills/issues/30))
- `README` Contributing section — documents the `./setup.sh` + `make lint` + `make test` local workflow ([issues/30](https://github.com/couimet/my-claude-skills/issues/30))

## 2026.02.25

### Added

- `/github-ref` shared rule skill — all 9 output-generating skills now require full GitHub URLs for issue and PR references; never short-form `#NNN` or `PR #NNN` ([issues/25](https://github.com/couimet/my-claude-skills/issues/25))

## 2026.02.24

### Added

- CHANGELOG.md with CalVer versioning scheme and Keep a Changelog structure (#14)
- CI check that warns (non-blocking) when a PR doesn't update CHANGELOG.md (#14)
- Versioning section in README linking to this changelog (#14)
