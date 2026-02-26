# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to this project will be documented in this file.

This project uses [Calendar Versioning](https://calver.org/) with the format `YYYY.0M.0D` (e.g., `2026.02.24`). When multiple versions land on the same day, a micro suffix is appended: `2026.02.24.2`, `2026.02.24.3`, etc.

Entries are organized using [Keep a Changelog](https://keepachangelog.com/) categories: **Added**, **Changed**, **Fixed**, **Removed**. Not every release uses every category — include only the ones that apply.

Contributors are encouraged to add a changelog entry with their PR, but it's not required. CI will nudge you with a non-blocking reminder if CHANGELOG.md wasn't modified.

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
