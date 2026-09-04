---
name: create-jira-issue
version: 2026.09.02@026b73f
description: Create a Jira issue from a standardized draft or an inline title, mirroring a reference ticket when one is given, with pre-create review
argument-hint: <file-path-or-title>
allowed-tools: Read, Write, Glob, AskUserQuestion, Bash(git branch --show-current), Bash(mkdir -p *), Bash(date *), Bash(*/skills/issue-context/claude-work-root.sh *), mcp__atlassian__createJiraIssue, mcp__atlassian__getJiraIssue, mcp__atlassian__getJiraIssueTypeMetaWithFields, mcp__atlassian__getJiraProjectIssueTypesMetadata, mcp__atlassian__createIssueLink, mcp__atlassian__getIssueLinkTypes, mcp__atlassian__getAccessibleAtlassianResources, mcp__atlassian__lookupJiraAccountId, mcp__atlassian__getTransitionsForJiraIssue, mcp__atlassian__transitionJiraIssue
---

# Create Jira Issue

Create a Jira issue through the Atlassian MCP server. Reads from the same standardized draft shape as `/create-github-issue` (authored by `/draft-issue`) and shares that skill's reading spine, then diverges completely below creation.

**Input:** $ARGUMENTS (a file path, or a title for interactive creation)

This skill requires the Atlassian MCP server to be connected. The MCP tool names below assume the server connects as `atlassian`, so each call is `mcp__atlassian__createJiraIssue` and so on. Use the names the connected server actually exposes. Because these servers are interactively authenticated, they may be absent in headless or cron runs in a way `gh` is not.

## Step 1: Parse the Draft

Follow `/issue-draft-reader`. It determines the input mode and returns the front-matter fields, the title, and the sanitized body. When the argument is a file that is not a standardized draft, the reader stops the flow and prints the route through `/draft-issue`, so no file reaching this step is unstandardized. Work with the returned fields, title, and body.

In inline-title mode, prompt the user for an optional description. If the user gives one, treat it as the body. If not, create title-only with an empty description.

## Step 2: Resolve cloudId and the Project Key

Resolve `cloudId` without prompting whenever possible. Call `getAccessibleAtlassianResources`. If exactly one resource is returned, take its `id` unconditionally. The site hostname also works directly as `cloudId` in place of the UUID. Prompt only when more than one site is returned.

Resolve the project key from the fields and the branch, in order:

- A `target-project` field wins. It is also the fallback for a detached head or a non-conforming branch name.
- Otherwise, read it from the `like` field's ticket's project.
- Otherwise, when the current branch matches `<KEY>-<slug>`, read the key from its first segment: `Bash(git branch --show-current)`.
- Otherwise, prompt the user for the project key.

Resolve the issue type from an `issue-type` field, else from the `like` field's ticket, else default to `Task`, since Jira has no default issue type the way GitHub has a default issue kind. A `like` field is an explicit author choice that implies both project and type. It is authoritative over branch inference. Only an explicit `target-project` or `issue-type` field outranks it.

If the returned fields name a GitHub target (`target-repo`) but no `target-project` or `like`, the draft targets GitHub: STOP and tell the user to run `/create-github-issue` with the same path.

## Step 3: Resolve the Field Payload

**When a `like` field exists, mirror the reference ticket.** Fetch its key with `getJiraIssue` requesting all fields and keep only its non-null fields. Call `getJiraIssueTypeMetaWithFields` with `requiredFieldsOnly: false` for the target project and issue type, which returns exactly the fields creatable there. Intersect the two sets: everything in both goes to the create call, with custom fields passed through `additional_fields`. This fills both the required fields and the optional-but-conventional fields that every real ticket sets, which discovery alone can never reveal. Mirror the ticket's metadata only. Do not mirror its `summary` and `description`. Set summary from the draft title and description from the draft body. This ticket then carries the draft's own content instead of duplicating the reference ticket's. Never pass the whole response blob: it contains values that cannot be set at creation (the development panel populated by the GitHub integration, plus `votes`, `watches`, `worklog`, `progress`, `workratio`, `statuscategorychangedate`, `lastViewed`).

**When no like field is given, assemble the payload from the draft.** Summary is the title, description is the body, and the issue type and project come from Step 2.

When an `assignee` field is present, or the like ticket names an assignee and no `assignee` field is present, resolve the account id with `lookupJiraAccountId` so `assignee_account_id` can be set.

## Step 4: Save the Payload and Confirm

Use `/note` with description `issue-payload` to save the resolved payload to a timestamped file under `.claude-work` (summary, sanitized description with the Generated-by footer, target project and issue type, parent, and custom fields), then print the note path and confirm with the user before creating. Always confirm, not conditionally. Jira creation is harder to undo than GitHub's: deleting an issue leaves a permanent hole in the key sequence, and a ticket filed against the wrong project cannot be moved without admin rights on some sites. This review is the one moment a human sees exactly what will be submitted.

The saved payload and the confirmation must also cover the Step 6 dependency links. For each `blocked-by` entry, list the target that will block this issue. For each `is-blocking` entry, list the target that this issue will block. Give each target with its resolved Jira key and link direction. The pre-create review must surface every tracker change the run will make. It must show the creation and the links that follow it alike. Nothing should happen after sign-off that the user has not seen.

Before saving, append a footer line to the description identifying the skill that generated it, preceded by a blank line. Read the `version:` field from this SKILL.md's front matter to fill `<VERSION>`:

```text

Generated by /create-jira-issue v<VERSION> • [my-claude-skills](https://github.com/couimet/my-claude-skills)
```

## Step 5: Create the Issue

Call `createJiraIssue` with the confirmed payload. `summary` and `description` are inline string parameters. `description` caps at 32000 chars. There is no body-file equivalent, so read the description from the note. Use `contentFormat: "markdown"`. GitHub conventions like `#123` references and task-list checkboxes do not carry over. Pass `parent` inline when a `parent` field was given. The `parent` parameter is set at creation, so no post-hoc sub-issue call is needed.

**When creation fails on a missing required field, do not prompt and do not surface the raw error.** Call `getJiraIssueTypeMetaWithFields` once with `requiredFieldsOnly: true`. Print the full list of required fields with their allowed values, then exit. The user fixes the draft and re-runs. Surfacing the bare error puts the user in a retry loop. Each attempt costs a round trip and may reveal only the next missing field. Printing the whole requirement set costs the same single call and ends the loop after one failure.

## Step 6: Link Dependencies

For each dependency relationship the draft declares against another Jira ticket, call `getIssueLinkTypes` to confirm the site's link-type names rather than assuming one, then link with `createIssueLink` using the confirmed type. Direction is the trap: for "A is blocked by B", `inwardIssue` is B and `outwardIssue` is A, which reads backwards from the natural sentence. Each entry in the `blocked-by` list is a ticket this issue waits on, and each entry in the `is-blocking` list is a ticket this issue unblocks. Entries are Jira issue keys; if one is a full URL, read the key from its tail.

## Step 7: Report

Print the created ticket's browse URL and key. The GitHub-for-Jira integration populates the Development panel automatically when a branch is named `<KEY>-<slug>`, so no explicit PR-link step is needed.

Formatting: see `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.
