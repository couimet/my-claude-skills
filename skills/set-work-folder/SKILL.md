---
name: set-work-folder
version: 2026.09.16@ae50bfe
description: Point this session's or this worktree's working files at a folder, instead of letting the current git branch decide where they go
argument-hint: '<folder> [name] | --clear | --worktree <folder> | --clear --worktree'
allowed-tools: Bash(*/skills/issue-context/set-work-folder.sh *)
---

# Set Work Folder

Point this session's or this worktree's working files at a folder of your choosing. Notes, questions, scratchpads, and commit-message drafts then go there instead of to the folder the current git branch implies.

**Input:** $ARGUMENTS (a folder path, optionally followed by a short name; `--clear`; `--worktree <folder>`; or `--clear --worktree`)

## When to Use

Use this when the branch is the wrong thing to organise by. A repository organised by topic is the case this exists for: the branch says nothing about which topic you are working on, so without an override the files scatter. Set the folder once, at any point in the session, and everything written afterwards follows it.

## When NOT to Use

Do not use this to redirect one file. An override is a property of a session or a checkout, not of a call, and it stays in force until it is cleared. If you want one file somewhere specific, write it there directly.

## Which Form to Use

The bare form sets a **session** folder: it lives until this session ends, and it is the one to reach for when the redirection is for today's work. `--worktree` sets a **worktree** folder: it writes `CLAUDE_WORK_FOLDER` at the root of the checkout you are in, and it lives until you delete it, which is the one to reach for when a checkout always belongs to one topic. A session folder outranks a worktree marker when both are set.

The marker is a plain file at the worktree root and it is deliberately not gitignored. It appears in `git status` until you clear it, which is the point: a setting that outlives your session is one you should be reminded you made. Two worktrees of the same repository can carry different markers, or one can carry none, because the file sits at each worktree's own root rather than in the shared `.claude-work/`.

## Step 1: Run the Script

```bash
~/.claude/skills/issue-context/set-work-folder.sh $ARGUMENTS
```

Pass an absolute path to a directory that already exists, optionally followed by a short name. A relative path and a missing directory are both refused rather than created, so a typo fails while you are still looking at it.

The name is optional and cosmetic. It goes into the stored file's name to make the sessions directory readable. Nothing is ever looked up by it, so it does not have to stay accurate. With no name given, the script reads one from the session's own job state when that is available, and otherwise leaves it off.

`--clear` removes the session override, and `--clear --worktree` removes the worktree marker. Each clears only its own tier, so clearing a session folder leaves a marker in force. Clearing when nothing is set is not an error.

`--worktree <folder>` takes the same absolute, must-already-exist path and refuses the same mistakes, for the same reason: a typo should fail while you are looking at it. It needs no session, so it works in a plain shell, and it refuses to run outside a git repository, where there is no worktree root for the file to live at. What it writes is the canonicalised path; a marker you write by hand may start with `~/` and it expands on read.

## Step 2: Report

Print what the script said on stderr, which names the folder now in force or confirms the clear. Print the file path from stdout only when the user asks where the setting is kept.

## What Callers See Afterwards

Every skill that writes a working file resolves its folder through the same path helper, so none of them need to know an override exists. See `/issue-context-internals` for the resolution order and the rules an override has to satisfy.

Two behaviors are worth stating plainly, because they surprise people:

**The override is session-wide, not per-agent.** Subagents launched through the Agent tool run in the same process and inherit the session identity, so a subagent that sets a folder changes it for its parent and for its siblings as well. The stored file records which agent wrote it, which is how a folder that changed unexpectedly gets traced afterwards.

**Naming a work item bypasses the override.** A caller that resolves a folder by work-item identifier, rather than from the session, gets that work item's folder. This is what keeps a folder deletion or a pointer read addressed at the work item the user named, rather than at whatever the session was pointed at. The path helper says on stderr when it has bypassed an override, so the difference is never silent.

**An override is ignored rather than obeyed when it does not apply.** A folder that has been deleted falls through to the next tier and says so. There is no containment rule: an override may name any existing absolute directory, in any repository or none, which is what makes a topic folder in one repository usable from a checkout of another.

**Cleaning up a work item under a worktree marker removes less than it looks like.** Marker placement is flat, so every work item's notes and questions sit together, and only the pointers and the breadcrumb live in the per-item folder. `/cleanup-issue` says so at its confirmation prompt rather than letting a completed cleanup read as more than it was.
