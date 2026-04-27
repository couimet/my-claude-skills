---
name: changelog
version: 2026.04.27@2c12606
description: Create or update CHANGELOG entries with tone guardrails, thematic grouping, and implementation-detail leak detection.
argument-hint: <description>
allowed-tools: Read, Edit, Bash(git log *), Bash(git diff *), Bash(git branch --show-current), AskUserQuestion
---

# Changelog

Create a CHANGELOG entry with built-in guardrails for tone, placement, and detail-leak detection. Writes directly to CHANGELOG.md — the user reviews via `git diff` before committing.

**Input:** $ARGUMENTS (a short description of the change, e.g. "binding survives language-mode changes")

## Step 1: Locate CHANGELOG.md

Find the target CHANGELOG.md using git diff to determine which part of the project has changes:

1. Run `git diff --name-only` to see changed files
2. If all changes are within a single package directory (e.g., `packages/foo/`), look for a CHANGELOG.md in that directory first
3. If changes span multiple packages, or no package-level CHANGELOG.md exists, fall back to the root CHANGELOG.md
4. If multiple package-level CHANGELOGs could apply (changes span packages that each have their own CHANGELOG), ask via `AskUserQuestion` which one to target

If no CHANGELOG.md exists anywhere, STOP: "No CHANGELOG.md found. Create one first."

## Step 2: Read CHANGELOG Structure

Read the target CHANGELOG.md and the project's CLAUDE.md (if it exists) to understand:

- **Versioning scheme** — detect from the file's own header or preamble. Common patterns:
  - **SemVer:** headings like `## [1.2.3]` or `## [Unreleased]`, often with a preamble referencing [semver.org](https://semver.org) or [Keep a Changelog](https://keepachangelog.com)
  - **CalVer:** headings like `## 2026.03.19`, often with a preamble referencing [calver.org](https://calver.org)
  - **Other:** match whatever heading pattern the file uses
- **Category subsections** — typically `### Added`, `### Changed`, `### Fixed`, `### Removed` (Keep a Changelog style). Some projects use different categories — match what exists.
- **Entry format** — how entries are written, how issue links are formatted, what style the project uses.
- **Existing entries** — scan the most recent section(s) to understand the project's voice and level of detail.

Also check the project's CLAUDE.md for any explicit CHANGELOG conventions (heading format, link style, category rules). CLAUDE.md overrides inferred conventions.

## Step 3: Detect Subsection

Auto-detect the most likely category from context:

| Signal | Category |
| --- | --- |
| New files added (`git diff --name-status` shows `A`) | Added |
| Bug fix (issue labels, commit messages mentioning "fix") | Fixed |
| Deleted files or removed features | Removed |
| Everything else | Changed |

**If the detection is confident** (clear signal from the table above), proceed without prompting.

**If ambiguous** (e.g., a file was both added and modified, or the change could be "Added" or "Changed"), confirm with `AskUserQuestion`:

```text
AskUserQuestion(
  question: "Which CHANGELOG category for this entry?",
  header: "Category",
  options: [
    { label: "Changed (Recommended)", description: "Modifications to existing behavior" },
    { label: "Added", description: "New features or files" },
    { label: "Fixed", description: "Bug fixes" },
    { label: "Removed", description: "Deleted features" }
  ]
)
```

Reorder options so the auto-detected category appears first with "(Recommended)".

## Step 4: Determine Version Heading

Determine where to place the entry based on the versioning scheme detected in Step 2:

**SemVer projects (with `[Unreleased]` section):**

- If an `## [Unreleased]` section exists, place the entry there — this is the standard SemVer workflow for in-progress changes.
- If no `[Unreleased]` section exists, create one above the most recent versioned heading.

**CalVer projects (date-based headings):**

- If today's date heading already exists, check for micro suffixes. Create a new heading with the next micro suffix (e.g., `2026.03.19` exists → `2026.03.19.1`; `2026.03.19.1` exists → `2026.03.19.2`).
- If today's date heading doesn't exist, create a new one above the most recent heading. Use the date format matching existing headings (read from CLAUDE.md or infer from the file).

**Other schemes:**

- Match the existing heading pattern. If uncertain, ask the user via `AskUserQuestion`.

## Step 5: Draft the Entry

Write the entry following the tone rules (see Tone Rules section below). The entry should:

1. Lead with what the user sees or experiences
2. Be one sentence for the change, optionally one for previous behavior
3. End with an issue reference following the project's link format (read from existing entries to match the convention)

Before drafting, read 3-5 recent entries in the CHANGELOG to match the project's voice and formatting conventions.

## Step 6: Implementation-Detail Check

Scan the draft entry against the blocklist patterns (see Implementation-Detail Blocklist section). For each match:

- Print a warning: `Possible implementation detail: "<matched text>" — consider rephrasing in user-facing terms`
- Do NOT block — the user may have a legitimate reason to include the detail

If no matches, proceed silently.

## Step 7: Thematic Placement

Scan the entries in the target section's category subsection for thematic proximity:

1. Look for entries about the same feature, component, module, or user workflow
2. If a match is found, place the new entry adjacent to the closest match (after it)
3. If no match is found, append at the end of the subsection

When creating a new version heading, placement is straightforward — the entry is the first in its subsection.

## Step 8: Present and Write

Show the user what will be written and where:

```text
File: packages/foo/CHANGELOG.md
Category: ### Changed
Heading: ## [Unreleased]
Placement: after "existing related entry text..." (thematic match)
Entry:
- Search results now highlight matched terms ([#42](https://github.com/org/repo/issues/42))
```

Then write the entry to CHANGELOG.md using the Edit tool.

## Tone Rules

These rules ensure entries describe what users experience, not how the code works internally.

### Do

- **Lead with what the user sees:** "Binding survives language-mode changes" not "Fixed onDidCloseTextDocument firing during language-mode switch"
- **Describe the symptom, not the mechanism:** "no longer silently breaks" not "now checks isClosed flag before re-registering"
- **One sentence for the change, optionally one for previous behavior** — no more
- **Use the feature name as the subject** when the change is about a specific feature

### Don't

- Name internal APIs, event handlers, class names, or flags in the entry text
- Explain the architecture or implementation approach
- Include file paths or function names (the git diff shows those)
- Write more than two sentences

### Examples

**Good (SemVer project — a task management app):**

```text
- Search results now highlight matched terms in the preview pane ([#42](https://github.com/acme/taskflow/issues/42))
```

**Bad (same change, leaking implementation):**

```text
- Added ElasticSearch highlight fragments to SearchResultDTO and mapped them through the PreviewRenderer pipeline with dangerouslySetInnerHTML for term emphasis ([#42](https://github.com/acme/taskflow/issues/42))
```

**Good (CalVer project — a CLI tool):**

```text
- `deploy` command now retries on transient network errors instead of failing immediately ([issues/87](https://github.com/acme/shipit/issues/87))
```

**Bad (same change, leaking implementation):**

```text
- Wrapped the HTTP client's POST call in a retry loop with exponential backoff using the got library's retry option with a maxRetryAfter of 30000ms and calculateDelay hook ([issues/87](https://github.com/acme/shipit/issues/87))
```

## Implementation-Detail Blocklist

Flag entries containing these patterns. Warn but do not block — rare edge cases may legitimately include a technical name.

| Pattern | Why it's flagged |
| --- | --- |
| `onDid`, `onWill` | Event handler names (VS Code, etc.) |
| `setTimeout`, `setInterval`, `requestAnimationFrame` | Timer/scheduling implementation details |
| `mock`, `stub`, `spy` | Test infrastructure, not user-facing |
| `listener`, `handler`, `callback`, `middleware` | Internal architecture |
| `PascalCase` words that aren't feature names | Likely class/type names (e.g., `SearchResultDTO`, `PreviewRenderer`) |
| `flag`, `isFoo`, `hasFoo` | Internal boolean state |
| Event name patterns (`Event`, `Emitter`, `dispatch`) | Internal pub/sub details |
| Library-internal APIs (`dangerouslySetInnerHTML`, `useEffect`, `__dirname`) | Framework internals |

## Thematic Grouping Rules

Before placing an entry, scan the target subsection for thematic proximity:

1. **Same feature or command name** — entries mentioning the same feature, command, or module name are the strongest match
2. **Same user workflow** — entries about the same user-facing workflow (e.g., "search", "deploy", "authentication")
3. **Same component area** — entries about the same part of the system (e.g., "CI", "build", "tests", "config")

Place the new entry after the last thematic match in the subsection. If no match exists, append at the end.

## Formatting

See `/prose-style` for hard-wrap and GitHub-reference rules.
