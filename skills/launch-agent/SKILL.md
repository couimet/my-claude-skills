---
name: launch-agent
description: Dispatch a background agent in one call. Creates the topic folder, saves the launch prompt in it, and sets the display name.
argument-hint: '<folder> [--name <display-name>] <task prompt>'
allowed-tools: Bash(*/skills/launch-agent/launch-agent.sh *)
---

# Launch Agent

Start a background agent on a topic. Four things are ready before the agent runs. The topic folder exists. The launch prompt is saved in it. The agent points its own working files at that folder. The agent has a display name you can find it by.

**Input:** $ARGUMENTS (a folder, then an optional `--name <display-name>`, then the task prompt)

## When to Use

Use this when work moves to a background agent and you must find that agent again later. The same four steps done by hand are four steps to forget. An agent started with no name appears as an unnamed row days later. A launch prompt that nobody saved is lost when the terminal scrolls.

## When NOT to Use

This skill starts a new session. It does not resume one. It passes no `claude` flag to the agent, so a different model or permission mode is a settings change and not an argument here. For a subagent inside the current session, use the Agent tool instead. A subagent shares this session's identity and returns its result to you.

## The Folder

The folder holds the agent's notes, questions, scratchpads, and commit-message drafts. The agent's first action points its working files there. See `/set-work-folder` for what that setting does and how long it lasts. See `/issue-context` for the resolution order behind it.

The folder takes one of two forms.

A **slug** is a single name. It resolves to a directory of that name at the root of the repository you are in. Use a slug in a repository organised by topic, where topic folders sit at the root. Do not use a slug in a code repository. There the folder lands beside the source tree and stays in `git status`.

The script uses an **absolute path** exactly as you give it, in any directory, inside a repository or outside one. Use an absolute path in a code repository, where the folder usually belongs under `.claude-work/`. An absolute path also bypasses every refusal below. The script reads it as a deliberate choice and not as a name that could be a typo.

A slug must be a single path component. The script refuses a slug that contains a separator. It refuses `.` and `..`. It also refuses a slug that nearly matches a directory already at the root, and the message names the directory it matched. Without that refusal, `agent-launch-skill` beside an existing `agent_launch_skill` becomes a second topic. An exact match is not a refusal, because a second agent on an existing topic is normal.

## The Prompt

The task prompt is every argument after the folder and the optional `--name`. One argument that names a readable file is a special case. The script reads that file and uses its content as the prompt. This form carries a long prompt without shell quoting. Save a long prompt as a `/note` first, then give its path here.

The script refuses one argument that looks like a path and names no readable file. Without that refusal, a mistyped path becomes the agent's whole prompt, and nobody finds out until someone reads the agent's transcript.

The script saves the prompt to `prompt-new-agent-launch.txt` in the folder before it starts the agent. The file is therefore present even when the launch fails. The script first archives a prompt already at that name under its own modification time. The plain name always holds the latest launch, and no earlier prompt is lost.

## Step 1: Dispatch

```bash
~/.claude/skills/launch-agent/launch-agent.sh $ARGUMENTS
```

Every refusal happens before the script writes anything. A rejected launch leaves no folder and no file.

The display name defaults to the folder's basename. `claude agents` lists the agent under this name, and the terminal title shows it. The script also gives the name to the agent as the label for its own working files.

## Step 2: Report

The script prints the resolved folder first, so a mistyped path shows in the first line. It then prints the prompt file, the display name, the job id, and the attach command. Give these to the user as the script printed them.

A failed launch leaves the folder and the prompt file in place. It prints the exact command on stderr, ready to paste and run by hand. Give the user that command and do not rewrite it. The command carries the composed agent prompt, which is longer than what the user typed.

## Formatting

See `/prose-style` for hard-wrap and reference rules.
