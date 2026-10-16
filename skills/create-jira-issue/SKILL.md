---
name: create-jira-issue
version: 2026.10.16@0c25292
description: Create a Jira issue from a standardized draft or an inline title, mirroring a reference ticket when one is given, with pre-create review
argument-hint: <file-path-or-title> [--expect-sha256 <hex>]
allowed-tools: Read, Write, Glob, AskUserQuestion, Bash(git ls-files *), Bash(mkdir -p *), Bash(date *), Bash(*/skills/issue-context/branch-issue-id.sh *), Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/issue-context/get-issue-folder-path.sh *), Bash(*/skills/issue-context/claude-work-root.sh *), mcp__atlassian__createJiraIssue, mcp__atlassian__editJiraIssue, mcp__atlassian__getJiraIssue, mcp__atlassian__getJiraIssueTypeMetaWithFields, mcp__atlassian__getJiraProjectIssueTypesMetadata, mcp__atlassian__createIssueLink, mcp__atlassian__getIssueLinkTypes, mcp__atlassian__getAccessibleAtlassianResources, mcp__atlassian__lookupJiraAccountId, mcp__atlassian__getTransitionsForJiraIssue, mcp__atlassian__transitionJiraIssue, Bash(*/skills/prose-style/check-prose.sh *), Bash(*/skills/issue-context/skill-version.sh *), Bash(*/skills/create-jira-issue/draft-sha256.sh *)
---

# Create Jira Issue

Create a Jira issue through the Atlassian MCP server. Reads from the same standardized draft shape as `/create-github-issue` (authored by `/draft-issue`) and shares that skill's reading spine, then diverges completely below creation.

**Input:** $ARGUMENTS (a file path, or a title for interactive creation, with an optional `--expect-sha256 <hex>`)

This skill requires the Atlassian MCP server to be connected. The MCP tool names below assume the server connects as `atlassian`, so each call is `mcp__atlassian__createJiraIssue` and so on. Use the names the connected server actually exposes. Because these servers are interactively authenticated, they may be absent in headless or cron runs in a way `gh` is not.

## Step 1: Parse the Draft

**Check the approved hash first.** A review tool, such as the `ticket-writing` plugin's draft mode, prints `SHA256: <hex>` for the text the author approved. Pass that value as `--expect-sha256 <hex>` to refuse a draft that changed after its review. Remove the flag and its value from the argument before anything else reads it.

- **No flag:** skip this check.
- **The flag with an inline title:** STOP and report that `--expect-sha256` needs a draft file, because an inline title has no approved draft to compare.
- **The flag with a file:** run the hash script on the file as it is on disk, before the reader changes anything:

  ```bash
  ~/.claude/skills/create-jira-issue/draft-sha256.sh "<path>"
  ```

  The script hashes the title line and the body, without the front matter, by the same rule as the review tool. Compare its digest with the expected one in lowercase. When they differ, STOP before the reader runs. Print both digests, and say that the draft changed after its review, so the author must review it again. When they match, the draft is approved text: tell the reader to run in strict mode.

**Read the draft.** Follow `/issue-draft-reader`. It determines the input mode and returns the front-matter fields, the title, and the sanitized body. When the argument is a file that is not a standardized draft, the reader stops the flow and prints the route through `/draft-issue`, so no file reaching this step is unstandardized. Work with the returned fields, title, and body.

In inline-title mode, prompt the user for an optional description. If the user gives one, treat it as the body. If not, create title-only with an empty description.

## Step 2: Resolve cloudId and the Project Key

Resolve `cloudId` without prompting whenever possible. Call `getAccessibleAtlassianResources`. If exactly one resource is returned, take its `id` unconditionally. The site hostname also works directly as `cloudId` in place of the UUID. Prompt only when more than one site is returned. If no resources are returned, no `cloudId` can be resolved: STOP and report that the connection returned no accessible Atlassian site — the authentication is likely missing Jira or Confluence scopes, or the account has no access to a site — and ask the user to re-authenticate or confirm site access before re-running. Do not continue to payload resolution or `createJiraIssue` without a `cloudId`.

Resolve the project key from the fields and the branch, in order:

- A `target-project` field wins. It is also the fallback for a detached head or a non-conforming branch name.
- Otherwise, read it from the `like` field's ticket's project.
- Otherwise, resolve the work-item identifier from the current branch with `branch-issue-id.sh`:

  ```bash
  ~/.claude/skills/issue-context/branch-issue-id.sh
  ```

  When it prints an identifier shaped like a Jira key (letters, hyphen, digits — e.g. `PROJ-123`), take the letter prefix as the project key. A numeric or slug identifier carries no project, so fall through to the prompt.
- Otherwise, prompt the user for the project key.

Resolve the issue type from an `issue-type` field, else from the `like` field's ticket, else default to `Task`, since Jira has no default issue type the way GitHub has a default issue kind. A `like` field is an explicit author choice that implies both project and type. It is authoritative over branch inference. Only an explicit `target-project` or `issue-type` field outranks it.

If the returned fields name a GitHub target (`target-repo`) but no `target-project` or `like`, the draft targets GitHub: STOP and tell the user to run `/create-github-issue` with the same path.

## Step 3: Resolve the Field Payload

**Fetch the field metadata for every draft.** `getJiraIssueTypeMetaWithFields` takes an issue type id, not a name. Resolve the id of the Step 2 issue type from `getJiraProjectIssueTypesMetadata` for the target project. Then call `getJiraIssueTypeMetaWithFields` once for that project and issue type id. Pass `requiredFieldsOnly: true` when the draft has no `like` field and no `jira-fields` field. Pass `requiredFieldsOnly: false` otherwise, because the `like` mirror and the `jira-fields` names also need the optional fields. The rest of this step reads from this one response.

**When a `like` field exists, mirror the reference ticket.** Fetch its key with `getJiraIssue` requesting all fields and keep only its non-null fields. The metadata response from above returns exactly the fields creatable for the target project and issue type. Intersect the two sets: everything in both goes to the create call, with custom fields passed through `additional_fields`. This fills both the required fields and the optional-but-conventional fields that every real ticket sets, which discovery alone can never reveal. Mirror the ticket's metadata only. Do not mirror its `summary` and `description`. Set summary from the draft title and description from the draft body. This ticket then carries the draft's own content instead of duplicating the reference ticket's. Never pass the whole response blob: it contains values that cannot be set at creation (the development panel populated by the GitHub integration, plus `votes`, `watches`, `worklog`, `progress`, `workratio`, `statuscategorychangedate`, `lastViewed`).

**When no like field is given, assemble the payload from the draft.** Summary is the title, description is the body, and the issue type and project come from Step 2.

**When a `jira-fields` field exists, resolve each entry by display name.** Match each name to a field `name` in the metadata response to get its field id. For a field with allowed values, match the value to an allowed value's name to get its option id. Pass each resolved field through `additional_fields`, in the shape the field's schema expects. A `jira-fields` entry wins over the same field from the `like` ticket. When a name matches no field, STOP and print the field names the metadata allows. When a value matches no allowed value, STOP and print the allowed values for that field. Do not guess a near match: a wrong field value files a wrong ticket.

**Ask for each required field that nothing sets.** A required field is set when a draft field, a `jira-fields` entry, or the `like` ticket gives it a value. Skip the fields that the create call always sets: project, issue type, summary, and reporter. For each required field that is still empty, ask the user to pick a value with `AskUserQuestion`. Give up to three allowed values as options. The user types any other allowed value through "Other". Put the picked values in the Step 4 payload note only. Do not write them back to the draft file. This check runs before the create call, so a missing required field never costs a failed create.

When an `assignee` field is present, or the like ticket names an assignee and no `assignee` field is present, resolve the account id with `lookupJiraAccountId` so `assignee_account_id` can be set.

## Step 4: Save the Payload and Confirm

Use `/note` with description `issue-payload` to save the resolved payload to a new file (summary, sanitized description with the Generated-by footer, target project and issue type, parent, custom fields, and each required field with the value the user picked in Step 3 and the allowed values it came from), then print the note path and confirm with the user before creating. Always confirm, not conditionally. Jira creation is harder to undo than GitHub's: deleting an issue leaves a permanent hole in the key sequence, and a ticket filed against the wrong project cannot be moved without admin rights on some sites. This review is the one moment a human sees exactly what will be submitted.

The saved payload and the confirmation must also cover the Step 7 dependency links. For each `blocked-by` entry, list the target that will block this issue. For each `is-blocking` entry, list the target that this issue will block. Give each target with its resolved Jira key and link direction. The pre-create review must surface every tracker change the run will make. It must show the creation and the links that follow it alike. Nothing should happen after sign-off that the user has not seen.

Before saving, append a footer line to the description identifying the skill that generated it, preceded by a blank line. Fill `<VERSION>` from `~/.claude/skills/issue-context/skill-version.sh create-jira-issue`:

```text

Generated by /create-jira-issue v<VERSION> • [my-claude-skills](https://github.com/couimet/my-claude-skills)
```

Before the payload note is saved and confirmed, count the assembled description: the sanitized body plus the footer above. When it exceeds 32000 characters, STOP and report that the draft's body, with the Generated-by footer, is over Jira's 32,000-character description cap, and ask the user to trim the draft and re-run. Do not truncate the description to fit: an auto-shortened body would file an incomplete ticket, and the confirmed payload must stay faithful to the draft.

## Step 5: Create the Issue

**Check the hash again when Step 1 checked it.** The author can edit the draft while Step 4 waits for confirmation. Run `draft-sha256.sh` on the file again, immediately before the create. When the digest differs from the expected one, STOP before the create. Print both digests, and say that the draft changed after its check.

Call `createJiraIssue` with the confirmed payload. `summary` and `description` are inline string parameters. `description` caps at 32000 chars. There is no body-file equivalent, so read the description from the note. GitHub `#123` references do not carry over. Pass `parent` inline when a `parent` field was given. The `parent` parameter is set at creation, so no post-hoc sub-issue call is needed.

Choose the description format from the body:

- **The body has no task list:** use `contentFormat: "markdown"` and pass the description as text.
- **The body has a `- [ ]` or `- [x]` line:** use `contentFormat: "adf"`. The markdown converter stores a task item as escaped text, not as a checkbox. Convert the whole description to an ADF `doc`. Each run of task lines becomes a `taskList` node, and each line becomes a `taskItem` node with state `TODO` for `- [ ]` and `DONE` for `- [x]`. Give each `taskList` and `taskItem` node a unique `attrs.localId`, such as a UUID: the ADF schema requires it, and Jira rejects a task node without it. Convert the other blocks to their ADF nodes, and keep the Generated-by footer as the last paragraph.

**When creation fails on a missing required field, do not prompt and do not surface the raw error.** Step 3 asks for every required field before the create, so this is a backstop for a field the metadata did not show as required. Call `getJiraIssueTypeMetaWithFields` once with `requiredFieldsOnly: true`. Print the full list of required fields with their allowed values, then exit. The user fixes the draft and re-runs. Surfacing the bare error puts the user in a retry loop. Each attempt costs a round trip and may reveal only the next missing field. Printing the whole requirement set costs the same single call and ends the loop after one failure.

## Step 6: Read Back the Ticket

Run this step after every create, with or without an expected hash. Call `getJiraIssue` for the new key with `responseContentFormat: "markdown"`. Confirm two facts:

- The stored summary equals the draft title.
- The stored description, without the Generated-by footer, matches the draft body. Normalize whitespace and markdown escapes on both sides before you compare, because Jira stores the text in its own form.

When Step 5 created with `contentFormat: "adf"`, also call `getJiraIssue` with `responseContentFormat: "adf"` and confirm that the description holds a `taskList` node. When it does not, patch the description with `editJiraIssue`, `contentFormat: "adf"`, and the same ADF `doc`, then read it again.

On a difference that remains, do not edit or delete the ticket: it already exists, and a silent repair would hide the difference from the user. Report each difference in Step 8 with the browse URL, so the user can fix the ticket in Jira.

## Step 7: Link Dependencies

For each dependency relationship the draft declares against another Jira ticket, call `getIssueLinkTypes` to confirm the site's link-type names rather than assuming one, then link with `createIssueLink` using the confirmed type. Direction is the trap: for "A is blocked by B", `inwardIssue` is B and `outwardIssue` is A, which reads backwards from the natural sentence. Each entry in the `blocked-by` list is a ticket this issue waits on, and each entry in the `is-blocking` list is a ticket this issue unblocks. Entries are Jira issue keys; if one is a full URL, read the key from its tail.

## Step 8: Report

Print the created ticket's browse URL and key. The GitHub-for-Jira integration populates the Development panel automatically from a branch whose name contains the key (the branch created for the work carries it), so no explicit PR-link step is needed. When Step 6 found a difference, print each difference after the URL.

Formatting: see `/prose-style` for hard-wrap, code-reference, and GitHub-reference rules.
