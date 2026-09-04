---
name: draft-issue
version: 2026.09.02@026b73f
description: Author an issue draft in the standardized local format, a YAML-style front-matter block over a markdown title and body, grill the content through `/g2q` for thoroughness, then file it with `/create-github-issue` or `/create-jira-issue`
argument-hint: <title-or-file-path>
allowed-tools: Read, Write, Glob, AskUserQuestion, Bash(git branch --show-current), Bash(mkdir -p *), Bash(date *), Bash(*/skills/issue-context/claude-work-root.sh *), Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/ensure-gitignore/ensure-gitignore.sh *)
---

# Draft Issue

Author an issue draft in a standardized local format so the creation skills read structured fields instead of guessing from prose. `/create-github-issue` and `/create-jira-issue` accept a standardized draft file or a bare inline title. A file that is not yet standardized must pass through this skill first. A draft is grilled through `/g2q` for thoroughness before it is written, so the filed issue starts complete instead of one line.

**Input:** $ARGUMENTS (an issue title, or a path to an existing file to import)

For a defaults-only creation you do not need this skill: pass the title inline to the creation skill. Use `/draft-issue` when the issue needs a body, a target, or any structured field, or when you have a file to convert.

## The Standardized Draft Format

A draft is a note file whose content is a YAML-style front-matter block over a markdown body, the same shape as every SKILL.md file in this collection. The front matter carries the machine fields. The title is the body's first `#` heading. Prose never enters the front matter. Drafts are `note`-typed files, so `/note` resolves where the draft lands and `/file-placement` treats it as a note.

The front-matter field reference, shown commented, is what a scaffolded draft carries when no field is set yet:

```text
---
# target-repo: owner/repo    Target repository for /create-github-issue (default: current remote)
# target-project: KEY        Jira project key for /create-jira-issue (default: branch prefix)
# issue-type: Task           Jira issue type (default: Task, or the like ticket's type)
# assignee: <id-or-email>    Jira assignee
# like: KEY-123              Jira ticket to mirror fields from
# parent: <url-or-key>       Parent issue or ticket
# blocked-by:                Dependencies this issue waits on, one per line
#   - <url-or-key>
# is-blocking:               Dependencies this issue unblocks, one per line
#   - <url-or-key>
---
```

An example draft with fields set shows the active form:

```text
---
target-project: COUIM
issue-type: Story
parent: COUIM-88
is-blocking:
  - COUIM-90
---

# Draft a feature with a standard local format

Authoring steps below produce this shape.
```

Set a field by writing it as an active line and dropping its comment marker. Values use the target tracker's reference form: full GitHub issue URLs for `/create-github-issue`, Jira keys for `/create-jira-issue`. A list field's entries sit on indented `-` lines under the key, one entry per line. Creation skills read the keys they understand and ignore the rest, then strip the whole front-matter block before filing.

## Step 1: Determine the Input Mode

Check whether `$ARGUMENTS` points to an existing file (any path, any extension or none). If it does, import-and-wrap that file. Otherwise scaffold from the bare title.

## Step 2: Compose the Title and Body

**Scaffold from a bare title:** set the title to `$ARGUMENTS`. Then invite the author to compose the body now. The grill in Step 3 needs content to challenge, so gather the issue's substance before writing: ask what the issue must communicate — the problem it solves, the expected behavior, and any acceptance criteria — and draft the body from the author's answer. Keep the body empty only when the author explicitly supplies nothing.

**Import an existing file:** read the file first. A leading `---` front-matter block does not prove the draft was grilled. Every import must still clear the Step 3 grill. Derive the title and body:

- If the file opens with a `---` front-matter block, step past it and take the first `#` heading after it as the title and everything after it as the body. Keep that front matter as the draft's machine fields. The grill judges prose, not fields, so keep those fields active through Step 5. Do not rebuild them as the commented template.
- Otherwise, if the file's first non-empty line is a `#` heading, that heading is the title and everything after it is the body.
- Otherwise the first non-empty line is the title and everything after it is the body.

For a file without front matter, insert the derived title and body under a fresh front-matter block in the standard shape. This keeps drag-dropped scratchpads, markdown files, and older unstandardized drafts usable as issues. Preserve the imported body verbatim; do not reflow or rewrite the author's prose. Either way, continue to Step 3 and grill the imported content like any other draft.

## Step 3: Grill the Draft for Thoroughness

Run `/g2q` on the composed draft, passing the title and body as its topic. The grill challenges the content for gaps a reader would hit, the same thoroughness gate `/start-issue` applies to its plan. Follow the `/g2q` report:

- When it reports no questions raised, the content is thorough enough. Proceed to Step 4.
- When it reports questions raised, share the returned questions file with the author and collect their answers. Fold each answer into the body so the resolution lives in the draft text itself, then run `/g2q` again over the updated content. Repeat until it reports no questions raised.

The draft note is not written until this grill is clean. The grill judges the issue body. Step 4 collects the machine fields the grill does not see.

## Step 4: Collect Machine Fields

Ask whether the author wants to set any machine fields now, using `AskUserQuestion` with two options: set fields now, or fill them in the file later. When the author chooses to set fields now, prompt once for whichever of these they want: target repo or project, issue type, assignee, parent, like ticket, blocked-by dependencies, is-blocking dependencies. Add each answer as an active front-matter field. When the author fills fields later, leave the commented template in place. Either way the body and title from Step 2 stay unchanged.

## Step 5: Write the Draft

The note content is the composed draft: the front matter (active fields when the author set them, otherwise the commented field-reference block), a blank line, the `# <title>` heading, a blank line, then the grilled body (empty for a bare-title scaffold the author left empty, the folded and imported content otherwise). Never copy the example body text from this skill into a draft. Follow `/note` with description set to the title to persist the draft. `/note` writes the timestamped file, resolves the notes directory from the current branch and the shared `.claude-work/` root, and prints the absolute path. Do not print the file contents.

## Step 6: Report

Print only the absolute draft path. Then state the next step in one line:

```text
Edit the draft to finish the body and fields, then file it by running /create-github-issue <path> or /create-jira-issue <path>.
```

Formatting: see `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.
