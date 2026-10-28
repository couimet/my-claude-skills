---
name: rename-agent
description: Give this session its folder name, or another name, at the next prompt. It renames only this session.
argument-hint: '[name]'
allowed-tools: Bash(*/skills/issue-context/rename-agent.sh *)
---

# Rename Agent

Give this session a name in place of a typed `/rename`. With no argument, the name is the folder name of the bound folder, which is the usual fix.

**Input:** $ARGUMENTS (an optional name)

## When NOT to Use

This skill renames only the session that runs it. For another session, rename nothing, and give the user this step: open that session, and run `/rename-agent` in it.

## Step 1: Run the Script

```bash
~/.claude/skills/issue-context/rename-agent.sh $ARGUMENTS
```

The script records the name for this session. The session hook sets it at the next prompt and gives no warning about it. Without the session hook, the name does not apply: tell the user to install the hook (see the README).

## Step 2: Report

Give the user the line that the script printed: the name applies at the next prompt. An error names its code. N003 means that this session has no folder: give the user the error, which names `/launch-agent` and `/set-work-folder`.

## Formatting

See `/prose-style` for hard-wrap and reference rules.
