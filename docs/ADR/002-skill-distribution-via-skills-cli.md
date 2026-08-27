# ADR 002: Skill Distribution via the Skills CLI

- **Status:** Accepted
- **Date:** 2026-08-25
- **Issue:** <https://github.com/couimet/my-claude-skills/issues/208>

## Context

The repository's skills are installed two ways: clone + `install.sh` (symlinks from `~/.claude/skills/` to the repo) and the Claude Code plugin marketplace. Issue 208 asks for a third path used by the skills.sh ecosystem: `npx skills add couimet/my-claude-skills --global`.

The skills CLI is a cross-agent installer. It discovers `SKILL.md` files in standard locations (`skills/`, `.claude/skills/`, repo root) and copies or symlinks each skill directory into the target agent's skills directory. It installs straight from the GitHub repository; the repo needs no npm package and no build step. The CLI tracks installed versions in a lockfile and provides `npx skills update` for consumers.

The issue also asked whether the CLI path forces per-skill changelogs and versioning.

## Decision

- **Distribute through the skills CLI straight from the GitHub repo.** No npm package, no publish pipeline, no CI release step.
- **Keep the repo as a single release unit.** One CHANGELOG, one CalVer version, one stamp workflow (`make stamp` / stamp-skills.yml). Per-skill changelogs and versioning are deferred until a skill needs to be consumed independently, which is a different product model.
- **Document the quick-install path in the README** alongside the existing clone + `install.sh` and plugin-marketplace paths.
- **Validate installability in CI** with a bats smoke test (`bats-tests/skills-cli.bats`) that pins the CLI version, asserts every skill is discoverable, and installs the suite into a temp HOME to prove companion scripts survive.

## Consequences

### Positive

- **Zero publishing infrastructure.** Consumers install from the repo, so there is no artifact to build, tag, or push. `npx skills update` and `git pull` both track the repo.
- **One release unit.** Skills stay coupled through shared conventions, scripts, and cross-references; a single CHANGELOG and stamp version avoid coordination cost without hurting consumers.
- **CI-guarded against CLI drift.** The smoke test pins the CLI version and fails the build if the CLI stops discovering skills or drops companion files. It also caught a real regression during implementation: the CLI's YAML parser rejects colon-space sequences in unquoted frontmatter values, which silently skipped three skills until their descriptions were quoted.
- **Complementary, not replacement.** Clone + `install.sh` stays the path for contributors and live checkouts; the marketplace path stays for prefix-namespaced installs.

### Negative

- **Consumers install from main.** No per-consumer version pinning beyond the CLI's own lockfile. A breaking change to a skill ships to everyone on `npx skills update`.
- **Two tools manage the same directory.** The CLI installs into the same `~/.claude/skills/` that `install.sh` manages. Mixing both paths for the same skill can conflict; the README tells users to pick one.
- **Hook skills ship with the suite.** The repo's project-level `.claude/skills/finish-issue-hook` is discovered and installed too. It is a foundation skill (`user-invocable: false`) and harmless globally, but it is a deliberate part of the distributable set.
- **CLI behavior is out of our control.** The pinned version in the bats test needs periodic bumps as the CLI evolves.

## Alternatives Considered

### CI publishing pipeline (rejected)

Issue 208 proposed automating publishing on merge to main. There is nothing to publish: the CLI installs from the repository, so a release step would be machinery for an artifact that does not exist. If a custom installer or npm package is ever needed, this becomes the right mechanism, but it is not needed today.

### Per-skill npm packages (rejected)

Publishing skills to npm is a real ecosystem pattern (for example, [@jesdi/skills](https://www.npmjs.com/package/@jesdi/skills) ships a content package plus its own installer CLI, with CI publishing on merge to main), so the rejection is about this repo's consumer flow, not the pattern itself. The skills CLI reads git sources, so an npm artifact of our skills would have no consumer in the `npx skills add` flow; using it would require building and maintaining our own installer CLI. If an npm artifact is ever needed (custom installer, enterprise proxy, offline mirror), it carries a SemVer package version while the per-skill CalVer stamps stay untouched; the two versioning schemes are independent. Deferred until that need exists.
