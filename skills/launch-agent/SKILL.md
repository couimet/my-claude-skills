---
name: launch-agent
version: 2026.10.20@b191fa8
description: Start work on a topic in one call, in this session or with --bg in a background agent. Creates the topic folder, saves the launch prompt in it, and names the work after the folder.
argument-hint: '[--bg] [--take-over] <folder> <task prompt>'
allowed-tools: Bash(*/skills/launch-agent/launch-agent.sh *)
---

# Launch Agent

Start work on a topic with four things already in place. The topic folder exists. The launch prompt is saved in it. The working files point at that folder. The work carries the folder's name, so you can find it again.

**Input:** $ARGUMENTS (the optional flags `--bg` and `--take-over`, then a folder, then the task prompt)

## Two Modes

The default starts no agent. It creates the folder, saves the prompt, and then points **this** session's working files at that folder. The session that ran the skill is the session that does the work, and `claude agents` gains no row.

`--bg` starts a background agent. **This session does not become that agent.** This session stays where it is, and the work runs somewhere else. Step 2 reports the job id that reaches it again.

## When to Use

The user or Claude can start this skill. **When Claude starts it with no request from the user, Claude passes `--bg`.** The default mode moves this session's working files to the new folder, so during a task it sends the notes of the task there with no warning. The script cannot tell who called it, so only this rule enforces it.

Use the default when the work is yours to do now, in the session you already sit in, and you want the folder, the saved prompt, and the name set up first. This is the usual case.

Use `--bg` when work moves to a background agent and you must find that agent again later.

## When NOT to Use

`--bg` starts a new session. It does not resume one. It passes no `claude` flag to the agent. For a subagent inside the current session, use the Agent tool instead. A subagent shares this session's identity and returns its result to you.

To point this session at a folder without starting a topic, see `/set-work-folder`. That skill sets the folder alone.

## The Depth Limit

`--bg` refuses with L006 when the new agent would go past the `launchAgentMaxDepth` setting (default 2). A session the user started is depth 0. See `/issue-context-internals`. On an L006 refusal, do not retry in another form: record the work in the folder of this session, and tell the user.

## The Folder

The folder holds the notes, questions, scratchpads, and commit-message drafts of the work. The name of the work is always the folder's basename.

An absolute path is used as given. A slug resolves under `launchAgentDefaultFolder`, or else under the repository root. Without the setting, do not use a slug in a code repository: the folder lands beside the source tree and stays in `git status`.

## The Prompt

The task prompt goes to the script on standard input, through a quoted heredoc (Step 1). The shell changes nothing between the quoted marker and its end line, so URLs, slash commands, `?`, `&`, and apostrophes all reach the script as the user typed them.

A person who runs the script by hand can pass the prompt as arguments. Its header gives the rules.

The prompt is saved in the folder before the work starts, so it is there even when the launch fails. The first prompt keeps `prompt-new-agent-launch.txt`. Each later launch adds `prompt-new-agent-launch.txt.update-<stamp>.txt`, which sorts after it. A repeat of the newest prompt adds nothing. No saved prompt is ever changed.

## Step 1: Run the Script

Split `$ARGUMENTS` into three parts: the flags `--bg` and `--take-over` when they come first, the folder, and the task prompt (all the text after the folder, exactly as the user typed it). The folder is the first word after the flags. When the user quotes it, the folder is the whole quoted string, spaces included, without the quotes. When `--bg` or `--take-over` comes right after the folder, run nothing, and tell the user that each flag now comes before the folder.

Check each line of the task prompt before you build the command. If a line is exactly `LAUNCH_AGENT_PROMPT_END`, run nothing. Tell the user which line collides with the heredoc marker. The check is necessary because that line ends the heredoc early, and the shell then runs every later line of the prompt as a command.

Run the script with the prompt between the markers:

```bash
~/.claude/skills/launch-agent/launch-agent.sh [--bg] [--take-over] "<folder>" <<'LAUNCH_AGENT_PROMPT_END'
<task prompt>
LAUNCH_AGENT_PROMPT_END
```

Keep the quotes around the first marker. They stop all shell expansion inside the prompt. Do not pass the prompt as an argument, and do not write it to a file first.

Every refusal happens before the script writes anything, in both modes. A rejected call leaves no folder and no file.

## Step 2: Report

Give the user the lines the script printed, as it printed them: the resolved folder, the prompt file, and the name. Give the `Repeat:` line and the `/resume-agent` hint for an earlier session too, when printed.

The default mode adds one line saying that no agent started, and one `Type /rename <name> ...` line. Print both. Claude Code gives a script no way to rename a session, so only the user can type that command. This session now owns the folder, so do the task the user gave you. Then repeat the `/rename` line, unchanged, as the last line of your first reply that gives control back to the user: a finished result, a question, or a stop for approval. Repeat it only that once.

`--bg` adds the job id and the attach command. Print both, and say plainly that this session did not become the agent, so the user knows where the work went. `claude agents` lists the agent under the name, so no `/rename` is necessary.

The script refuses with L007 when another running or `retired` session holds the folder. On L007, give the user the error and stop. Pass `--take-over` only when the user asks. It takes the folder from another session, never from this one, and prints a `claude stop` line. Give the user its `took` line, or with `--bg` its `takeover dispatched` line.

A failed call leaves the folder and the prompt file in place. It prints the exact command on stderr, ready to paste and run by hand. Give the user that command unchanged. With `--bg` it carries the composed agent prompt. An L004 or L006 that says the agent started means the agent runs: do not launch again, record the work here, or give a `claude --bg` command. Point the user to `claude agents` and to the L006 `claude stop` command.

## Formatting

See `/prose-style` for hard-wrap and reference rules.
