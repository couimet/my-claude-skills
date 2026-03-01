# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to this project will be documented in this file.

This project uses [Calendar Versioning](https://calver.org/) with the format `YYYY.0M.0D` (e.g., `2026.02.24`). When multiple versions land on the same day, a micro suffix is appended: `2026.02.24.2`, `2026.02.24.3`, etc.

Entries are organized using [Keep a Changelog](https://keepachangelog.com/) categories: **Added**, **Changed**, **Fixed**, **Removed**. Not every release uses every category — include only the ones that apply.

Contributors are encouraged to add a changelog entry with their PR, but it's not required. CI will nudge you with a non-blocking reminder if CHANGELOG.md wasn't modified.

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
