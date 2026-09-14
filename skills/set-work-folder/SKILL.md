---
name: set-work-folder
description: Point this session's working files at a folder, instead of letting the current git branch decide where they go
argument-hint: '<folder> [name] | --clear'
allowed-tools: Bash(*/skills/issue-context/set-work-folder.sh *)
---

# Set Work Folder

Point this session's working files at a folder of your choosing. Notes, questions, scratchpads, and commit-message drafts then go there instead of to the folder the current git branch implies.

**Input:** $ARGUMENTS (a folder path, optionally followed by a short name, or `--clear`)

## When to Use

Use this when the branch is the wrong thing to organise by. A repository organised by topic is the case this exists for: the branch says nothing about which topic you are working on, so without an override the files scatter. Set the folder once, at any point in the session, and everything written afterwards follows it.

## When NOT to Use

Do not use this to redirect one file. The override is a property of the session, not of a call, and it stays in force until it is cleared. If you want one file somewhere specific, write it there directly.

## Step 1: Run the Script

```bash
~/.claude/skills/issue-context/set-work-folder.sh $ARGUMENTS
```

The script takes an absolute path to a directory that already exists, optionally followed by a short name. It refuses a relative path and refuses a directory that does not exist, rather than creating one, so a typo fails while you are still looking at it.

The name is optional and cosmetic. It goes into the stored file's name to make the sessions directory readable. Nothing is ever looked up by it, so it does not have to stay accurate. With no name given, the script reads one from the session's own job state when that is available, and otherwise leaves it off.

`--clear` removes the override, and the next working file goes back to branch-derived placement. Clearing when nothing is set is not an error.

## Step 2: Report

Print what the script said on stderr, which names the folder now in force or confirms the clear. Print the file path from stdout only when the user asks where the setting is kept.

## What Callers See Afterwards

Every skill that writes a working file resolves its folder through the same path helper, so none of them need to know an override exists. See `/issue-context` for the resolution order and the rules an override has to satisfy.

Two behaviors are worth stating plainly, because they surprise people:

**The override is session-wide, not per-agent.** Subagents launched through the Agent tool run in the same process and inherit the session identity, so a subagent that sets a folder changes it for its parent and for its siblings as well. The stored file records which agent wrote it, which is how a folder that changed unexpectedly gets traced afterwards.

**Naming a work item bypasses the override.** A caller that resolves a folder by work-item identifier, rather than from the session, gets that work item's folder. This is what keeps a folder deletion or a pointer read addressed at the work item the user named, rather than at whatever the session was pointed at. The path helper says on stderr when it has bypassed an override, so the difference is never silent.

**An override is ignored rather than obeyed when it does not apply.** A folder that has been deleted, or one belonging to a different repository than the one being resolved in, falls back to branch-derived placement and says so. Working in a second repository with an override set for the first is the ordinary way to meet this.
