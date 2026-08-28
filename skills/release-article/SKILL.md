---
name: release-article
version: 2026.08.26@a664832
description: Gather release context (changelog, README, prior articles, promotion registry) and draft a dev.to article with promotion copy and cross-repo registration handoff
argument-hint: <release-version-or-issue-url>
allowed-tools: Read, Write, Glob, Grep, AskUserQuestion, Bash(git branch --show-current), Bash(git rev-parse *), Bash(mkdir -p *), Bash(date *), Bash(gh repo view *), Bash(gh issue view *), Bash(gh issue list *), Bash(gh label list *), Bash(gh issue create *), Bash(gh api repos/couimet/couimet.github.io/contents/_data/*), Bash(*/skills/create-github-issue/link-sub-issue.sh *), Bash(*/skills/create-github-issue/link-dependency.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *), Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/issue-context/claude-work-root.sh *)
---

# Release Article

Gather context for a software release and produce publication-ready drafts: a dev.to article, a prioritized change summary, social media copy, a "Featured In" entry, and a `promotions.yml` entry. When run outside `couimet/couimet.github.io`, optionally propose a cross-repo registration handoff via `/create-github-issue`. This skill **drafts only** — it never publishes, posts, or modifies existing files without explicit approval.

**Input:** `$ARGUMENTS` (optional). A release version or tag (e.g., `2.1.0`), or a release-writing reminder issue URL (e.g., the [couimet/rangeLink #727](https://github.com/couimet/rangeLink/issues/727) pattern). When omitted, the target release is the latest version heading in the changelog.

## Step 1: Resolve Context

Run these commands as parallel tool calls:

```bash
gh repo view --json owner,name
```

```bash
git branch --show-current
```

```bash
~/.claude/skills/issue-context/claude-work-root.sh
```

Use the stdout of `claude-work-root.sh` as `<base>` for all `.claude-work/` paths in this skill. Record whether the current repo is `couimet/couimet.github.io` (it decides whether Step 8 applies).

Determine the target release when `$ARGUMENTS` names one:

- When `$ARGUMENTS` is a version or tag, use it.
- When `$ARGUMENTS` is an issue URL, validate that it matches `https://github.com/{owner}/{repo}/issues/{number}` before running any command. Fetch it with `gh issue view "$ARGUMENTS" --json title,body` — the validated URL always goes as a single quoted argument — and use its stated release (the issue may name the draft template file and the README update, as in the [rangeLink #727](https://github.com/couimet/rangeLink/issues/727) pattern). Validate the extracted release against the expected release format `v?<major>.<minor>.<patch>` (e.g., `2.1.0` or `v2.1.0`). If the issue states no release, or the stated value does not match that format, **STOP** and ask the user via `AskUserQuestion` which release to target before proceeding.

Locate the changelog. Start at the repo root `CHANGELOG.md`. When `$ARGUMENTS` names a release, verify the root changelog contains a heading for that exact release, not merely that it has version headings, and that the matching section holds detailed release entries rather than being index-only: a section with no `### Added`/`### Changed`/`### Deprecated`/`### Removed`/`### Fixed`/`### Security` subsections whose bullets are all markdown links carrying no `(#NNN)` references or prose is index-only and does not qualify the root. In a monorepo the root changelog is often only an index, so when the root has no version headings, does not contain the requested release, or its matching section is index-only, scan `packages/*/` for a package that pairs a `CHANGELOG.md` with a README containing a "Featured In" section. When several packages match, narrow the candidates against the requested release or tag when `$ARGUMENTS` names one, and always against the project identity: the package whose changelog contains the target release and whose README names the product being released. When `$ARGUMENTS` is empty, the same detailed-entries test applies to the latest version heading in the root changelog, and discovery narrows by project identity and README context only. If multiple candidates still match, ask the user via `AskUserQuestion` which changelog to use before proceeding. If no package candidate matches, **STOP** and ask the user via `AskUserQuestion` which changelog to use. If no changelog at all (root or packages) holds detailed entries for the requested release, **STOP** and ask the user via `AskUserQuestion` for the correct source or release. The index-only test applies to the root changelog only; package candidates are presumed detailed. Report which changelog was used, stating when the root section was index-only and drove the selection.

When `$ARGUMENTS` is empty, use the latest version heading in the located changelog.

## Step 2: Resolve the Article Output Location

The output location is **never guessed**. Read the target repo's `CLAUDE.md` (when present) and look for a section that names `release-article` and defines where the skill's outputs go, including naming conventions (e.g., `media/devto-post-<product>-<version>.md`).

- If the section exists, use its location and naming rules for the article draft, after validating the resolved path: it must be a project-relative destination inside the target repository or inside the documented `<base>` working area. Reject absolute paths and `..` traversal outside those roots. If `CLAUDE.md` names an external destination, **STOP** and ask the user via `AskUserQuestion` for explicit approval before any write.
- If it does not exist, **STOP** and prompt the user with `AskUserQuestion`:
  - **Define it now**: the user adds a `release-article` section to the target repo's `CLAUDE.md` (location + naming rules); wait for the edit, then use it.
  - **Use the fallback**: write drafts to the standard note location, `<base>/issues/<NNN>/notes/` on an issue branch, else `<base>/notes/`; the user moves the file later.

Do not hardcode `media/` or `articles/_sources/` as defaults. Report the resolved location and its naming convention in the final report.

## Step 3: Read and Prioritize the Changelog

Read the entries for the target release in the located changelog. Preserve the sub-section ordering: the author already orders entries by importance within `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, and `### Security`, so do not reorder them. Collect the `(#NNN)` issue references from each entry and resolve each one to its full GitHub URL before generating any draft, per `/prose-style` Rule 3: build `https://github.com/{owner}/{repo}/issues/{number}` from the current remote (e.g., `gh repo view --json url`). Produce the prioritized change summary by user impact, ordered headline feature first, with each item carrying its full issue URLs.

## Step 4: Gather Project Context

- **Terminology**: read the project README and note the exact product terms the article must preserve (no invented names).
- **"Featured In" format**: capture the exact README section format (newest first, `- [Title](url) - DEV Community` style).
- **Prior articles**: list prior article drafts in the Step 2-resolved output directory first, then in the project `media/` folder, then in `couimet.github.io/articles/_sources/`; skim them so the new article does not repeat already-covered ground.
- **Media assets**: list available screenshots and their naming conventions (e.g., `devto-post-<product>-<version>-<feature>.png`); note which changelog entries have visual support.

## Step 5: Read Tone and Registry Sources

The registry is public and always available. Prefer the local clone: resolve the current repo root (`git rev-parse --show-toplevel`), look for a sibling `couimet.github.io` directory (`../couimet.github.io/`), and read `_data/promotions.yml` and `_data/articles.yml` from it. When the sibling clone is absent, read the same files from the public repo via the GitHub API:

```bash
gh api repos/couimet/couimet.github.io/contents/_data/promotions.yml -H "Accept: application/vnd.github.raw"
```

```bash
gh api repos/couimet/couimet.github.io/contents/_data/articles.yml -H "Accept: application/vnd.github.raw"
```

From these files:

- The `content` values are the tone corpus: first-person, emoji, `👉 <url>` sign-offs, short paragraphs, occasional FR/EN variants. Match it.
- The distinct `projects` values are the only slugs that exist today; Step 7 reuses or extends them.
- The `anchor` slug is the join key between a promotion and its article.

Report which source was used (sibling clone or API). The tone corpus and `projects` values come from the registry either way; there is no degraded-mode fallback.

## Step 6: Draft the Article

Create the working document via `/note` with description `release-article-draft`. The draft carries YAML front matter (`title`, `published: TBD`, `tags`, `cover_image`), a narrative "What's New" structure that reorganizes the changelog by user impact, and only behaviors the changelog and repository sources support. No invented features.

Then write the deliverable file to the location resolved in Step 2, using the resolved naming convention (e.g., `media/devto-post-vscode-extension-2.1.0.md`), re-applying the Step 2 path validation to the destination immediately before writing; an external destination passes the re-validation only when Step 2 explicitly approved it via `AskUserQuestion`. Creating this new draft file is the workflow's deliverable and carries **no approval gate** — but only for first-time creation within a validated destination. Before writing, check whether the resolved path already exists. If it exists, do not overwrite it: stop and ask the user via `AskUserQuestion` whether to replace it, choose a different name, or edit the existing draft. Write automatically only when the path is absent. Reference companion screenshots from Step 4 where they support the copy.

## Step 7: Generate Promotion Drafts

All promotion drafts live in the Step 6 working document. Edits to **existing** files (README, `promotions.yml`, `articles.yml`, `CLAUDE.md`) are proposals, never direct writes.

- **Social media copy**: `linkedin` and `x` content in the tone of the Step 5 corpus.
- **`projects` value**: reuse an existing slug when it represents the source project; if several match, ask the user to select one; if none matches, propose a new value and require user confirmation. Never guess silently.
- **"Featured In" entry**: tracked in the working-document metadata as `published: TBD`, together with the prospective bullet in the Step 4 README format (`- [Title](url) - DEV Community`) using a title placeholder. The README bullet itself is proposed only once a real URL exists.
- **`promotions.yml` entry draft**: schema-valid (`date`, `context`, `anchor`, optional `summary` and `projects`, plus at least one of `linkedin`/`x` with `url` and `content`).
- **Inside `couimet/couimet.github.io`**: also propose the `articles.yml` entry (with the matching `anchor`) as a draft for approval.

## Step 8: Cross-Repo Registration Handoff (only outside couimet/couimet.github.io)

When the current repo is not `couimet/couimet.github.io`, help register the article in the central promotion backlog:

1. Determine the article status: `draft`, `published`, or `not created`. A draft is never described as published.
2. Duplicate-check `couimet/couimet.github.io` issues for an existing registration. Run one `gh issue list --repo couimet/couimet.github.io --state all --limit 100 --search "$identifier" --json number,title,body` per non-empty identifier — the source repository, the release version, and the public article URL when published — each identifier passed as a separate quoted argument, never embedded in a longer search expression — and inspect the titles and bodies of the results for a registration match. Skip the handoff only on a correlated match: an exact public article URL, or a single issue containing both the source repository and the release version. An isolated release-version match is not a duplicate, since versions are not unique across projects.
3. Only when no correlated match exists, write the handoff draft via `/note` with description `release-article-handoff`. The draft must contain: a `#` heading as title; a `**Target repo:** couimet/couimet.github.io` line; the source repository URL and name; the release version, tag, or changelog section; the local article path (the real project path, or a statement that the draft is local and not yet in the repository when the article lives at the Step 2 `.claude-work/` fallback — `.claude-work/` paths never appear in the draft, whose body becomes a GitHub issue); the public article URL when published; the article status; relevant release, PR, and issue URLs; the proposed `projects` value with the reason for it; a reference to the promotion copy draft; and a checklist for updating `_data/promotions.yml` and reviewing the centralized publishing tone.
4. Ask the user to confirm via `AskUserQuestion`. Only after confirmation, suggest:
   `/create-github-issue <handoff-draft-path>`
5. Never create the issue automatically. The duplicate check always runs; the handoff draft and confirmation prompt run only when no correlated match exists. The registry data in Step 5 comes from the sibling clone or the public API, so there is no missing-access branch.

## Step 9: Report and Approval Gate

Print the absolute path of the Step 6 working document once and identify the change summary, social media copy, "Featured In" entry, and `promotions.yml` entry draft sections within it. Print the absolute path of the article draft file and of the handoff note when applicable. List the assumptions and any missing source material.

**IMPORTANT: Do NOT publish to dev.to, do NOT post on social media, do NOT modify existing files (README, `promotions.yml`, `articles.yml`, `CLAUDE.md`), and do NOT create GitHub issues without explicit user approval.** The only automatic write to target project files is the new article draft when the Step 2-resolved path is absent (Step 6). The Step 6 working document and the Step 8 handoff draft are `/note` files under `.claude-work/` and are written automatically.

Wait for the user to review the drafts. Only proceed with a write to an existing path, an edit, or an issue creation the user explicitly asks for.

## Formatting

See `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.

## Quality Checklist

Before finishing, verify:

- [ ] Changelog located (root or per-package) with detailed entries for the requested release (index-only root sections rejected), and target release identified
- [ ] Article output location resolved from the target repo's `CLAUDE.md` or an explicitly confirmed fallback, never guessed
- [ ] Change summary preserves the changelog's importance ordering and carries `(#NNN)` links
- [ ] Tone corpus and `projects` values read from the sibling clone or the public API
- [ ] Article draft written to the resolved location with the resolved naming convention
- [ ] Promotion drafts match the tone corpus; `projects` value reused, selected, or confirmed
- [ ] Handoff draft produced when outside `couimet/couimet.github.io`, with a duplicate check performed
- [ ] No publication, existing-file edit, or issue creation without explicit approval
- [ ] Assumptions and missing material listed for the user
