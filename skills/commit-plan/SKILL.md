---
name: commit-plan
description: Print one commit line for each pending scoped /commit-msg message of the live Claude sessions in this working tree, in order, so the work of several sessions lands as one commit each. Never stages and never commits. Use when the user says "plan the commits", "commit the work of all sessions", or "one commit for each session".
allowed-tools: Bash(*/skills/commit-plan/commit-plan.sh *)
---

# Commit Plan

Several Claude sessions can change one working tree at the same time. Each session writes its own message with `/commit-msg` and a scope (`--path` and `--patch`). This skill collects the pending messages of all the live sessions and prints the command line of each commit, in order. **Never run a printed line, and never stage or commit yourself.** The user reads each line and runs it.

**Input:** none.

## Step 1: Consult the Hook

Consult `/commit-plan-hook` when the project has it. See `/skill-hooks`. The hook can only add, at two points:

1. **Excluded paths:** paths that no line stages, such as log files that the project commits with its own script. Pass each one to the script as `--exclude "<path>"`.
2. **First lines:** lines that the plan prints before its own lines, such as the command of that script.

With no hook, run the script with no argument.

## Step 2: Run the Script

```bash
~/.claude/skills/commit-plan/commit-plan.sh --exclude "<path>"
```

The script finds the sessions from their session files and the live rows of `claude agents --json`, in the working tree of the cwd. A session with no session file is not in the plan. The script runs the full plan in a temporary index, so the real index does not change. The script header gives each rule.

## Step 3: Report

Print the hook lines first, then the stdout of the script as it is: its `Plan for` line, one `!` line for each commit, and its `Not in the plan:` block. Tell the user to run the lines in order, one at a time. A `held: busy` session is still at work: run `/commit-plan` again when it is idle.

On an error, give the user the stderr line. U005 and U006 name two messages that take the same path or the same hunk: one of the two sessions must write its message again with another scope. U007 means that the index holds staged changes: the user unstages them first.

## Formatting

See `/prose-style` for hard-wrap and reference rules.
