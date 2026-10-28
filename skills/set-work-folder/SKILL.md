---
name: set-work-folder
version: 2026.10.22@b3b9515
description: Point this session's or this worktree's working files at a folder, instead of letting the current git branch decide where they go
argument-hint: '[--take-over] <folder> [name] | --clear | --worktree <folder> | --clear --worktree'
allowed-tools: Bash(*/skills/issue-context/set-work-folder.sh *)
---

# Set Work Folder

Point this session's or this worktree's working files at a folder of your choosing. Notes, questions, scratchpads, and commit-message drafts then go there instead of to the folder the current git branch implies.

**Input:** $ARGUMENTS (an optional `--take-over`, then a folder path, optionally followed by a short name; `--clear`; `--worktree <folder>`; or `--clear --worktree`)

## When to Use

Use this when the branch is the wrong thing to organise by. A repository organised by topic is the case this exists for: the branch says nothing about which topic you are working on, so without an override the files scatter. Set the folder once, at any point in the session, and everything written afterwards follows it.

## When NOT to Use

Do not use this to redirect one file. An override is a property of a session or a checkout, not of a call, and it stays in force until it is cleared. If you want one file somewhere specific, write it there directly. Naming a work item (`--id`) bypasses the session folder.

## Which Form to Use

The bare form sets a **session** folder: it lives until this session ends, and it is the one to reach for when the redirection is for today's work. `--worktree` sets a **worktree** folder: it writes `CLAUDE_WORK_FOLDER` at the root of the checkout you are in, and it lives until you delete it, which is the one to reach for when a checkout always belongs to one topic. A session folder outranks a worktree marker when both are set. A session keeps its folder after `/clear` when the session hook is installed. Without the hook, only a background session keeps it.

A marker can also hold a rule instead of a folder. A repository that keeps its working files in topic folders can commit a `CLAUDE_WORK_FOLDER` whose only line is `{"mode": "require-override"}`. Each session in that worktree must then set its own session folder before it writes a working file. A write with no session folder stops with error T104, which names the fix: run `/set-work-folder <absolute folder>`. To write to the branch folder on purpose, pass the branch folder that the T104 message names. On a work-item branch, it is the folder of that item under `.claude-work/`, not the `.claude-work/` root. `--worktree <folder>` refuses with S006 to replace a mode marker, and `--clear --worktree` removes it. Write a mode marker by hand: this skill sets no mode.

The marker is a plain file at the worktree root and it is deliberately not gitignored. It appears in `git status` until you clear it, which is the point: a setting that outlives your session is one you should be reminded you made. Two worktrees of the same repository can carry different markers, or one can carry none, because the file sits at each worktree's own root rather than in the shared `.claude-work/`.

## Step 1: Run the Script

```bash
~/.claude/skills/issue-context/set-work-folder.sh $ARGUMENTS
```

Pass an absolute path to a directory that already exists, optionally followed by a short name. A relative path and a missing directory are both refused rather than created, so a typo fails while you are still looking at it.

The name is optional and cosmetic. It goes into the stored file's name to make the sessions directory readable. Nothing is ever looked up by it, so it does not have to stay accurate. With no name given, the script reads one from the session's own job state when that is available, and otherwise leaves it off.

The session name is a different thing. When the session hook is installed, the session gets the folder name as its name at its next prompt, unless the user chose another name. A send by name then reaches the session that holds the folder. `/rename-agent` changes the session name.

One folder has one session. When another running or `retired` session holds the folder, the script stops with S007. The error names that session and the `/resume-agent <folder>` command that continues it. `--take-over <folder> [name]` claims the folder anyway: it removes the session files of the other session, and stderr gives the `claude stop <job id>` command for it.

`--clear` removes the session override, and `--clear --worktree` removes the worktree marker. Each clears only its own tier, so clearing a session folder leaves a marker in force. Clearing when nothing is set is not an error.

`--worktree <folder>` takes the same absolute, must-already-exist path and refuses the same mistakes, for the same reason: a typo should fail while you are looking at it. It needs no session, so it works in a plain shell, and it refuses to run outside a git repository, where there is no worktree root for the file to live at. What it writes is the canonicalised path; a marker you write by hand may start with `~/` and it expands on read.

## Step 2: Report

Print what the script said on stderr, which names the folder now in force or confirms the clear. On S007, give the user the error as it is, with its `/resume-agent` command and its `--take-over` command, and let the user choose: do not take the folder over unless the user asks. After a take-over, give the user the `claude stop` line. When the change leaves working files behind, stderr also says how many, where they stay, and where readers look now. Print that line as it is, because the user decides whether to move the files. Print the file path from stdout only when the user asks where the setting is kept.
