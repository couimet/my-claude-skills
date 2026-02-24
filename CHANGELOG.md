# Changelog

All notable changes to this project will be documented in this file.

This project uses [Calendar Versioning](https://calver.org/) with the format `YYYY.0M.0D` (e.g., `2026.02.24`). When multiple versions land on the same day, a micro suffix is appended: `2026.02.24.2`, `2026.02.24.3`, etc.

Entries are organized using [Keep a Changelog](https://keepachangelog.com/) categories: **Added**, **Changed**, **Fixed**, **Removed**. Not every release uses every category — include only the ones that apply.

Contributors are encouraged to add a changelog entry with their PR, but it's not required. CI will nudge you with a non-blocking reminder if CHANGELOG.md wasn't modified.

## Unreleased

### Added

- CHANGELOG.md with CalVer versioning scheme and Keep a Changelog structure (#14)
- CI check that warns (non-blocking) when a PR doesn't update CHANGELOG.md (#14)
- Versioning section in README linking to this changelog (#14)
