---
name: find-agent
description: Say which session holds a work folder, or what this session holds, and print the next command (launch, resume, attach, or rename). It changes nothing.
argument-hint: '[<folder>]'
allowed-tools: Bash(*/skills/issue-context/find-agent.sh *)
---

# Find Agent

Say which action fits a work folder before the user acts: `/launch-agent`, `/resume-agent`, `claude attach`, or `/rename-agent` in the holder.

**Input:** $ARGUMENTS (an optional folder: an absolute path, or a slug)

## Step 1: Run the Script

With a folder:

```bash
~/.claude/skills/issue-context/find-agent.sh "<folder>"
```

With no argument, for this session:

```bash
~/.claude/skills/issue-context/find-agent.sh
```

## Step 2: Report

Give the user each line that the script printed, in order. The `Verdict:` line holds one of `launch`, `resume`, `attach`, `running`, `rename`, `moved`, or `unbound`. The `Next:` line holds the command, and an `Or:` line holds the second choice. A `Holder:` line marks this session with `this`.

Do not run a command that the script printed. The user decides. An error names its code, G001 to G005: give the user the error as it is.

## Formatting

See `/prose-style` for hard-wrap and reference rules.
