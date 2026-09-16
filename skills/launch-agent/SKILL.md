---
name: launch-agent
description: Dispatch a background agent in one call, or set the same topic up in this session with --here. Creates the topic folder, saves the launch prompt in it, and sets the display name.
argument-hint: '<folder> [--name <display-name>] [--here] <task prompt>'
allowed-tools: Bash(*/skills/launch-agent/launch-agent.sh *)
---

# Launch Agent

Start work on a topic with four things already in place. The topic folder exists. The launch prompt is saved in it. The working files point at that folder. The work carries a display name you can find it by.

**Input:** $ARGUMENTS (a folder, then an optional `--name <display-name>` and an optional `--here` in either order, then the task prompt)

## Two Modes

The default starts a background agent. **This session does not become that agent.** This session stays where it is, and the work runs somewhere else. Step 2 reports the job id that reaches it again. If this session exists only to run this skill, the default leaves two rows in `claude agents`: this session, which then has nothing to do, and the agent that holds the work.

`--here` starts no agent. It creates the same folder, saves the same prompt, and then points **this** session's working files at that folder. The session that ran the skill is the session that does the work, and `claude agents` gains no row.

## When to Use

Use the default when work moves to a background agent and you must find that agent again later. The same four steps done by hand are four steps to forget. An agent started with no name appears as an unnamed row days later. A launch prompt that nobody saved is lost when the terminal scrolls.

Use `--here` when the work is yours to do now, in the session you already sit in, and you want the folder, the saved prompt, and the name set up first. Use it above all when the user invokes this skill from a session started for the purpose. The default gives that user a second session, and the first one is then theirs to stop.

## When NOT to Use

The default mode starts a new session. It does not resume one. It passes no `claude` flag to the agent, so a different model or permission mode is a settings change and not an argument here. For a subagent inside the current session, use the Agent tool instead. A subagent shares this session's identity and returns its result to you.

To point this session at a folder without starting a topic, see `/set-work-folder`. That skill sets the folder alone. This skill saves a launch prompt beside it, which is what makes the topic readable later.

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

## Step 1: Run the Script

```bash
~/.claude/skills/launch-agent/launch-agent.sh $ARGUMENTS
```

Every refusal happens before the script writes anything, in both modes. A rejected call leaves no folder and no file.

The display name defaults to the folder's basename. In the default mode `claude agents` lists the agent under this name and the terminal title shows it. In both modes the name becomes the label on the working files.

## Step 2: Report

The script prints the resolved folder first, so a mistyped path shows in the first line. It then prints the prompt file and the display name. Give these to the user as the script printed them.

The default mode adds the job id and the attach command. Print both, and say plainly that this session did not become the agent, so the user knows where the work went.

`--here` adds one line saying that no agent started. This session now owns the folder, so do the task the user gave you.

A failed call leaves the folder and the prompt file in place. It prints the exact command on stderr, ready to paste and run by hand. Give the user that command and do not rewrite it. In the default mode the command carries the composed agent prompt, which is longer than what the user typed.

## Formatting

See `/prose-style` for hard-wrap and reference rules.
