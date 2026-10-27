---
name: fork-side-item
version: 2026.10.22@b3b9515
description: Move a side item (a defect, a smell, or a docs gap found outside the current task) to its own side-<slug> folder with a background worker that owns it, then continue the task. A list mode shows the side folders and their state.
argument-hint: '<claim> | list'
allowed-tools: Read, Write, Edit, Bash(*/skills/fork-side-item/fork-side-item.sh *), Bash(gh issue list *), Bash(git remote *), Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/prose-style/check-prose.sh *)
---

# Fork Side Item

Move one side item out of this session at the moment you find it. A side item is a problem outside the task of this session: a defect, a smell, or a gap in the docs. The skill creates a folder for the item and starts a background worker in it. The worker owns the item until it files a ticket, adds to a ticket, sends a message to the owner, or drops the item. This session keeps one line that names the folder, and then it continues its task.

**Input:** $ARGUMENTS (the claim, with the evidence in the conversation; or `list`)

## When to Use

Use this when you find a problem that does not belong to your task and that needs more than one line to handle. Claude can start this skill with no request from the user.

Do not use it for a problem inside your task: fix that problem as part of the task. Do not use it when you are a side worker: a side worker records its own side items in its folder and reports them.

## Terms

- **Topic root:** the directory where `/launch-agent` creates each topic folder: the `launchAgentDefaultFolder` setting, or the repository root when the setting is empty.
- **Side folder:** `<topic root>/side-<slug>`. The slug comes from the claim, cut at 50 characters. The fixed `side-` prefix lets one glob find every side item.
- **Origin folder:** the work folder of this session, where the item was found.

## The Inputs

Collect these before Step 1:

- **Claim:** one sentence that states the problem.
- **Evidence:** what shows the problem: file references, command output, links.
- **Found in:** a URL or a file reference for the place where you found the item, with the commit when you know it.
- **Origin folder:** the absolute path of the work folder of this session.
- **Mode:** `new`, or `enrich` with a ticket key when a ticket for the item exists already.
- **Return:** `none`, or `ticket-link` when this session needs the link of the ticket that the worker files.

`--mode` and `--return` are enums, so a later value adds to the set.

## Hook Points

A project adds its own rules in a hook skill, `/fork-side-item-hook`. See `/skill-hooks`. The hook can only add requirements, at these four points:

1. **Refusal checks** (Step 1): a check that refuses a fork, for example for a security item that has its own process.
2. **Tracker search** (Step 2): a search of the project's own tracker for an existing ticket.
3. **Worker prompt lines** (Step 3): lines that the worker prompt must contain, such as the mapping of `ticket-link` to the project's own step tracking.
4. **After-fork steps** (Step 5): bookkeeping after the worker starts.

A hook is a soft check: nothing proves that Claude read it. A project that puts a safety gate in the hook also states the gate in its `CLAUDE.md`. When no hook exists, each step uses the default below.

## Step 1: Refusal Checks

Apply the refusal checks of the hook, when there is one. When a check refuses, do not fork. Tell the user why, and continue your task.

## Step 2: Search for an Existing Ticket

Use the tracker search of the hook, when there is one. With no hook, search the open GitHub issues of the repository where you found the item:

```bash
gh issue list --repo "<owner>/<repo>" --state open --search "<three to five keywords from the claim>" --limit 5
```

Get `<owner>/<repo>` from the found-in URL, or from `git remote get-url origin` in that repository. When the repository has no GitHub remote, skip the search.

When an open issue covers the same problem, set the mode to `enrich` with that issue number. When you are not sure, keep `new`: the worker checks again.

## Step 3: Compose the Worker Prompt

Fill this template. Add the prompt lines of the hook at the end.

```text
You own one side item. Work only on it.

Claim: <claim>
Evidence:
<evidence>
Found in: <found-in URL or reference>
Origin folder: <origin folder>
Mode: <new | enrich>
Ticket: <ticket key, for enrich only>
Return: <none | ticket-link>

Do these steps in order:

1. Check the claim again on the latest default branch. A side item is often found against an older commit.
2. For the mode enrich, compare the evidence with the ticket, and list only what the ticket does not have.
3. Choose one outcome: ticket (file a new ticket), enrich (add to the existing ticket), message (send a message to the owner), or drop (the claim is false or not worth the work; give the reason).
4. Do the outcome. For a ticket, draft it with /draft-issue, file it with /create-github-issue or /create-jira-issue, and keep the link. Add to a ticket with a comment.
5. Close the folder. Write one line to <side folder>/side-outcome.txt: the outcome, a TAB, then the link of the ticket or comment, or the reason for a drop.
6. When Return is ticket-link, append one line to <origin folder>/side-items.txt: side.closed: <side folder>, a TAB, the outcome, a TAB, the link. Only append; never change other lines in that file.

Do not fork side items of your own and do not start agents. When you find another side item, record it in your folder and report it.
```

When you do not know the topic root, run the list mode first: each line starts with it.

## Step 4: Run the Script

Check each line of the worker prompt. If a line is exactly `FORK_SIDE_ITEM_PROMPT_END`, rename that line and tell the user, because it ends the heredoc early. Then run:

```bash
~/.claude/skills/fork-side-item/fork-side-item.sh fork "<claim>" <<'FORK_SIDE_ITEM_PROMPT_END'
<worker prompt>
FORK_SIDE_ITEM_PROMPT_END
```

Keep the quotes around the first marker, so the shell expands nothing in the prompt. The script starts the worker through `/launch-agent` in the background mode. That skill creates the folder, saves the prompt as `prompt-new-agent-launch.txt`, names the worker after the folder, and applies the depth limit.

The script refuses with these codes:

- **F002:** the side folder exists, and the message gives its state. When it holds this item, do not fork again. When the item is different, reword the claim and run the script again. When the state is `open` and the worker ended, `/resume-agent` wakes it.
- **F004:** `/launch-agent` refused or failed, and its own error comes first. Read that error before you act. An L004 or L006 that says the agent started means that the worker runs: do not fork the item again, and give the user the error, which says how to stop the worker. Any other L006 means that no worker started, because of the depth limit or an unreadable depth record: give the user the error, record the item in your own folder, and continue.
- **F001** and **F003:** usage and topic-root errors. Give the message to the user.

## Step 5: After the Fork

Do the after-fork steps of the hook, when there is one.

Copy the `side.forked: <folder>` line the script printed into your active working document, the note or scratchpad of your task. When none is open, create one with `/note`. Then tell the user, in one line, that the worker started and where. Continue your task.

## List Mode

```bash
~/.claude/skills/fork-side-item/fork-side-item.sh list
```

The script prints one line for each `side-*` folder under the topic root: the folder, a TAB, and its state. The state is the outcome in `side-outcome.txt`, or `open` when the worker has not closed the folder. Give the lines to the user as printed. When a folder is open, stderr adds one line: `/resume-agent <folder>` wakes a worker that ended.

## Formatting

See `/prose-style` for hard-wrap and reference rules.
