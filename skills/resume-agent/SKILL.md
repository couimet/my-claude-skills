---
name: resume-agent
version: 2026.10.20.1@5b343e4
description: Make the session of a topic folder run again under its name, so the next round of work goes to the session that holds the earlier rounds. No shell command is necessary.
argument-hint: '<folder>'
allowed-tools: Bash(*/skills/resume-agent/resume-agent.sh *), Bash(claude stop *)
---

# Resume Agent

Make the session of a topic folder run again, so that the next round of work on the topic goes to the session that holds the chat context of the earlier rounds.

**Input:** $ARGUMENTS (a folder: an absolute path, or a slug)

## When to Use

Use this when a topic that `/launch-agent` started needs another round, such as a review that waited for the author, and the session of the topic ended. Without this skill, only a shell brings the session back: find the session id, run `claude --bg --resume <session id>`, then attach.

The user or Claude can start this skill. A restart sends only a `/rename` prompt with the folder name, so the session starts no work. A person can type `/resume-agent` in any session, also in the input box of the agent view, which `claude agents` opens. A skill that prepares the next round runs the script directly. See "For Callers".

## When NOT to Use

The skill sends no prompt other than that `/rename`, and does not attach. A skill runs inside one session, so it cannot move the person's terminal into another session. To start a new topic, use `/launch-agent`. A restart keeps the session id, so the agent depth of the session (see `/launch-agent`) does not change.

## The Folder

The folder is an absolute path or a slug. A slug resolves as in `/launch-agent`: under the directory of the `launchAgentDefaultFolder` setting when it is set, and under the root of the current repository when it is not. The folder must exist, because this skill never creates one.

## Step 1: Run the Script

```bash
~/.claude/skills/resume-agent/resume-agent.sh "<folder>"
```

The script finds the sessions of the folder, and leaves out this session. When more than one session used the folder, the newest one wins, and stderr names the others. The state decides the action:

- **Running:** the script restarts nothing, because a resume of a running session starts a copy.
- **Retired:** the job is listed with no process. Only `claude attach` wakes it, in a terminal. The script restarts nothing and prints `Status: retired`.
- **Ended:** the script runs `claude --bg --resume` on the first session id of the job, with the prompt `/rename <folder name>` and no flag, so the session wakes under the folder name, in one job record. A flag such as `--name` starts a copy, and a prompt does not. Without the `/rename`, a session named only by a typed `/rename` can wake with an automatic name, which a later AI title replaces. The script picks the start directory and checks it. R007 reports a mismatch.
- **Gone:** the job is not listed, and Claude Code deleted the transcript of the conversation that a resume loads (the `cleanupPeriodDays` setting). A resume gives an empty conversation with no history and no name, so the script restarts nothing and stops with R008. It does not resume an older session of the folder in its place, because an older session misses the later rounds.

Right after a restart, the list shows the session under its short id until the session loads its name. Until then, a search in the agent view and a send by name cannot find the session. So the script reads the list again for up to 15 seconds, and the `Name:` line gives only a name that the list shows. When the name does not load in that time, the script prints `Name: not loaded yet`, and stderr gives the name from the restart output when it has one.

## Step 2: Report

Give the user every line the script printed, on stdout and on stderr, in order.

Tell the user how to open the session: with the `Attach:` command, or in the agent view as the `Open:` line says. Give the `Rename:` line as it is, when the script printed one: the list does not show the folder name. Tell the user not to run `claude --bg --resume` for the session, because it starts a copy. Give a `claude rm` line to the user, and do not run it: it removes a job record and its worktree, and keeps the transcript.

An error names its code. R005 means that the restart failed, or that it started a copy: give the user the output the script printed, which names the copy to stop. R006 means that the restart ran, but the list read after it failed, so the script does not know whether the session runs. Do not run `claude --bg --resume` for the session, because a resume of a running session starts a copy. Run the skill again: it restarts nothing when the list shows the session. R007 means that the session restarted in another directory than the one the script chose, so the project settings do not apply to it. The session runs: give the user the error, which says how to stop the session or move it with `/cd`. R008 means that Claude Code deleted the transcript of the session, so its history is lost and nothing restarted. Give the user the error, which says how to start the work again with `/launch-agent`, and in which directory when the session started outside the repository of the folder. Do not run `claude --bg --resume` for the session, and do not resume another session of the folder in its place.

## Step 3: Stop the Helper Session

When a person types the skill in the agent view, the agent view starts a new background session to run it, and that helper session stays in the list. Stop it when both are true: this session is a background session, and the call of this skill is the first message of the conversation. You know the second fact from your own conversation.

```bash
claude stop "<the first 8 characters of $CLAUDE_CODE_SESSION_ID>"
```

Make this your last action, because the stop ends this session. When the stop fails, end with one line that says the person can stop the helper session.

## For Callers

A skill that prepares the next round calls the script directly, as callers of `launch-agent.sh` do:

1. Save the prompt in the topic folder first, so that the message is never the only copy.
2. Run `resume-agent.sh "<folder>"`.
3. Choose the address. Use the name from the `Name:` line only when it loaded and stderr names no other live session with that name. Otherwise use the `Address:` line. A short id is not a `SendMessage` address. With no usable name and no `Address:` line, ask the person.
4. Read the `Status:` line. When it is `idle`, the session waits at its prompt: send. For each other status, ask the person before you send. `busy` means a turn runs, and a prompt can change work that is half done. `waiting` means a permission prompt, and a prompt does not answer it. `retired` means the session has no process: give the person the `Attach:` command, and send nothing until the session runs. `unknown` means the list gave no status.
5. Send the prompt with `SendMessage` to the address from step 3.
6. Relay the `Rename:` line to the person, when the script printed one.

The `State:` value does not decide anything: a session at its prompt can show `blocked`.

## Formatting

See `/prose-style` for hard-wrap and reference rules.
