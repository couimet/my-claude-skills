---
name: launch-agent
version: 2026.10.01@01f61e4
description: Start work on a topic in one call, in this session or with --bg in a background agent. Creates the topic folder, saves the launch prompt in it, and names the work after the folder.
argument-hint: '<folder> [--bg] <task prompt>'
allowed-tools: Bash(*/skills/launch-agent/launch-agent.sh *)
disable-model-invocation: true
---

# Launch Agent

Start work on a topic with four things already in place. The topic folder exists. The launch prompt is saved in it. The working files point at that folder. The work carries the folder's name, so you can find it again.

**Input:** $ARGUMENTS (a folder, then an optional `--bg`, then the task prompt)

## Two Modes

The default starts no agent. It creates the folder, saves the prompt, and then points **this** session's working files at that folder. The session that ran the skill is the session that does the work, and `claude agents` gains no row.

`--bg` starts a background agent. **This session does not become that agent.** This session stays where it is, and the work runs somewhere else. Step 2 reports the job id that reaches it again.

## When to Use

Only the user can start this skill, by typing `/launch-agent`.

Use the default when the work is yours to do now, in the session you already sit in, and you want the folder, the saved prompt, and the name set up first. This is the usual case.

Use `--bg` when work moves to a background agent and you must find that agent again later. The same four steps done by hand are four steps to forget. An agent started with no name appears as an unnamed row days later. A launch prompt that nobody saved is lost when the terminal scrolls.

## When NOT to Use

`--bg` starts a new session. It does not resume one. It passes no `claude` flag to the agent, so a different model or permission mode is a settings change and not an argument here. For a subagent inside the current session, use the Agent tool instead. A subagent shares this session's identity and returns its result to you.

To point this session at a folder without starting a topic, see `/set-work-folder`. That skill sets the folder alone. This skill saves a launch prompt beside it, which is what makes the topic readable later.

## The Folder

The folder holds the notes, questions, scratchpads, and commit-message drafts of the work. See `/set-work-folder` for what that setting does and how long it lasts. See `/issue-context-internals` for the resolution order behind it.

The folder takes one of two forms.

A **slug** is a single name. When the `launchAgentDefaultFolder` setting is set, a slug resolves to a directory of that name under the setting's directory, from any repository. When the setting is not set, a slug resolves at the root of the repository you are in. See `/issue-context-internals` for the settings file. The setting holds one absolute path and expands nothing, so `~` and environment variables stay as written. The script refuses a relative value or a directory that does not exist, and writes nothing. It also refuses a slug when the settings file is there but cannot be read, because the setting can be in that file. A slug that names an existing symlink to a directory resolves to the link's target, which can sit outside the root, so read the resolved folder in the script's first line when a topic folder is a symlink. Without the setting, do not use a slug in a code repository. There the folder lands beside the source tree and stays in `git status`.

An **absolute path** is taken exactly as given, in any directory, inside a repository or outside one. It wins over the setting. An absolute path is read as a deliberate choice, so the refusals that guard a slug do not apply to it.

A slug must be a single path component. The script refuses a slug that contains a separator. It refuses `.` and `..`. It also refuses a slug that nearly matches a directory already at the root, and the message names the directory it matched. Without that refusal, `agent-launch-skill` beside an existing `agent_launch_skill` becomes a second topic. An exact match is not a refusal, because a second agent on an existing topic is normal.

The name of the work is always the folder's basename.

## The Prompt

The task prompt goes to the script on standard input, through a quoted heredoc (Step 1). The shell changes nothing between the quoted marker and its end line, so URLs, slash commands, `?`, `&`, and apostrophes all reach the script as the user typed them.

The script still reads a prompt given as arguments, for a person who runs it by hand. An argument that holds whitespace is always prompt text. One argument with no whitespace that names a readable file is a special case: the script uses that file's content as the prompt. One argument with no whitespace that looks like a path and names no readable file is refused, because a mistyped path would otherwise become the whole prompt. A bare URL as the whole prompt is refused for the same reason, and standard input is the fix.

The prompt is saved in the folder before the work starts, so it is there even when the launch fails. The first prompt keeps `prompt-new-agent-launch.txt`. Each later launch adds `prompt-new-agent-launch.update-<stamp>.txt`, and a repeat of the newest prompt adds nothing. No saved prompt is ever changed.

## Step 1: Run the Script

Split `$ARGUMENTS` into three parts: the folder, `--bg` when it comes next, and the task prompt (all the text after them, exactly as the user typed it). The folder is the first word. When the user quotes it, the folder is the whole quoted string, spaces included, without the quotes.

Check each line of the task prompt before you build the command. If a line is exactly `LAUNCH_AGENT_PROMPT_END`, run nothing. Tell the user which line collides with the heredoc marker. The check is necessary because that line ends the heredoc early, and the shell then runs every later line of the prompt as a command. The script cannot detect this, because it receives only the text above the marker.

Run the script with the prompt between the markers:

```bash
~/.claude/skills/launch-agent/launch-agent.sh "<folder>" [--bg] <<'LAUNCH_AGENT_PROMPT_END'
<task prompt>
LAUNCH_AGENT_PROMPT_END
```

Keep the quotes around the first marker. They stop all shell expansion inside the prompt. Do not pass the prompt as an argument, and do not write it to a file first.

Every refusal happens before the script writes anything, in both modes. A rejected call leaves no folder and no file.

## Step 2: Report

Give the user the lines the script printed, as it printed them: the resolved folder, the prompt file, and the name. Give the `Repeat:` line too, when the script prints it.

The default mode adds one line saying that no agent started, and one `Type /rename <name> ...` line. Print both. Claude Code gives a script no way to rename a session, so only the user can type that command. This session now owns the folder, so do the task the user gave you. Then repeat the `/rename` line, unchanged, as the last line of your first reply that gives control back to the user: a finished result, a question, or a stop for approval. Repeat it only that once. The script printed the line before the work started, and the user reads the first pause, not the launch output.

`--bg` adds the job id and the attach command. Print both, and say plainly that this session did not become the agent, so the user knows where the work went. `claude agents` lists the agent under the name, so no `/rename` is necessary.

A failed call leaves the folder and the prompt file in place. It prints the exact command on stderr, ready to paste and run by hand. Give the user that command and do not rewrite it. With `--bg` the command carries the composed agent prompt, which is longer than what the user typed.

## Formatting

See `/prose-style` for hard-wrap and reference rules.
