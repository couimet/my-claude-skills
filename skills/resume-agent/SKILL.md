---
name: resume-agent
description: Make the session of a topic folder run again under its name, so the next round of work goes to the session that holds the earlier rounds. No shell command is necessary.
argument-hint: '<folder>'
allowed-tools: Bash(*/skills/resume-agent/resume-agent.sh *), Bash(claude stop *)
---

# Resume Agent

Make the session of a topic folder run again, so that the next round of work on the topic goes to the session that holds the chat context of the earlier rounds.

**Input:** $ARGUMENTS (a folder: an absolute path, or a slug)

## When to Use

Use this when a topic that `/launch-agent` started needs another round, such as a review that waited for the author, and the session of the topic ended. Without this skill, only a shell brings the session back: find the session id, run `claude --bg --resume <session id>`, then attach.

The user or Claude can start this skill. A restart sends no prompt, so the session wakes idle and starts no work. A person can type `/resume-agent` in any session, also in the input box of the agent view, which `claude agents` opens. A skill that prepares the next round runs the script directly. See "For Callers".

## When NOT to Use

The skill sends no prompt and does not attach. A skill runs inside one session, so it cannot move the person's terminal into another session. To start a new topic, use `/launch-agent`. A restart keeps the session id, so the agent depth of the session (see `/launch-agent`) does not change.

## The Folder

The folder is an absolute path or a slug. A slug resolves as in `/launch-agent`: under the directory of the `launchAgentDefaultFolder` setting when it is set, and under the root of the current repository when it is not. The folder must exist, because this skill never creates one.

## Step 1: Run the Script

```bash
~/.claude/skills/resume-agent/resume-agent.sh "<folder>"
```

The script finds the session of the folder in the session files that `/set-work-folder` writes, and it skips the file of this session. When more than one session used the folder, the newest one wins, and stderr names the others. Then the script reads `claude agents --json`:

- **Listed:** the session runs. The script restarts nothing, because a resume of a running session starts a copy.
- **Not listed:** the session ended. The script runs `claude --bg --resume <session id>` with no prompt and no flag, so the session wakes idle under the name it was saved with. A flag such as `--name` makes Claude Code start a copy under a new id, which is why the script passes none.

## Step 2: Report

Give the user the lines the script printed: `Folder:`, `Session:`, `Id:`, `Name:`, `State:`, `Action:`, and `Open:`. Give the stderr lines too, when the script prints them: the other sessions of the folder, and a name that is not the folder name.

Tell the user how to open the session: in the agent view, press `Ctrl+F`, type the name, and press Enter.

An error names its code. R001 is a usage error. R002 means that the folder does not resolve or does not exist. R003 means that no other session wrote to the folder. R004 means that `claude agents --json` failed, so the script restarted nothing. R005 means that the restart failed, or that it started a copy: give the user the output the script printed, which names the copy to stop.

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
3. Send the prompt with `SendMessage` to the name the script printed. When the name is not the folder name, use the id from the `Id:` line.

When the state is `working` or `blocked`, ask the person before you send. A prompt that joins a turn in progress can change work that is half done. A blocked session waits for a permission answer, and a prompt does not give that answer.

## Formatting

See `/prose-style` for hard-wrap and reference rules.
