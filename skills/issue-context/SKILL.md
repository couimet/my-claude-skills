---
name: issue-context
version: 2026.09.16@ae50bfe
user-invocable: false
description: Contract for the two scripts that resolve where a working file goes - target-path.sh and claude-work-root.sh. Referenced by name from the skills that write working files.
allowed-tools: Bash(*/skills/issue-context/target-path.sh *), Bash(*/skills/issue-context/claude-work-root.sh *)
---

# Issue Context

All deterministic logic for "where should this file go?" lives in the scripts. A skill that writes a working file calls `target-path.sh`. A skill that needs only the `.claude-work/` root calls `claude-work-root.sh`.

## Script: target-path.sh

```bash
~/.claude/skills/issue-context/target-path.sh --type <scratchpads|questions|commit-msgs|notes> --description "<text>" [--ext txt]
```

The script resolves the work-item folder, slugifies the description, names the file, creates the target directory, and prints one path on stdout.

**Four properties callers can rely on.** These four are the contract. Every other detail of the returned path belongs to the script and can change without notice. The filename format is one such detail.

1. **Absolute.** You can print the path for the user. You can use it from any working directory.
2. **Directory exists and the path is reserved.** The script creates the directory and reserves the path, so the file is already there and empty when you get it. Write over that reservation. Do not create the directory, and do not read an empty file at a returned path as a working file: it is a reservation whose caller has not written yet.
3. **Unique.** The script never hands out a path that is already taken, and two calls never hand out the same path, even when they run at the same moment. The only file your write replaces is the empty reservation property 2 describes. Do not check the directory first. Do not edit an earlier file instead of creating a new one.
4. **Lexicographic order equals creation order.** A byte-order sort of a directory lists the files from oldest to newest. To find the newest file that matches a pattern, take the maximum. Skip a zero-byte candidate while you do, because the newest file matching your pattern is exactly the one most likely to be an unwritten reservation.

You never release a path you decide not to use. The script sweeps an abandoned reservation on a later call.

Placement resolves through three tiers, in order: the current session's folder override, this worktree's `CLAUDE_WORK_FOLDER` marker, then the branch context. A caller writes a working file the same way in every case, and the override and the marker are invisible to it. ADR 003 records why the tiers are ordered that way.

The next line is an example, not a specification. Read the filename format from `target-path.sh`. Do not read it from prose:

```text
/Users/x/project/.claude-work/issues/42/questions/20260909-101500-001-scope-question.txt
```

## Script: claude-work-root.sh

```bash
~/.claude/skills/issue-context/claude-work-root.sh
```

Returns the absolute path to the `.claude-work/` root directory, taking git worktrees into account, so every linked worktree of a repository shares one copy. The script outputs an absolute path on stdout. It does NOT create the directory; callers handle that.

A caller that needs only the root calls this script and appends its own subdirectory and filename.

## The other scripts

Further scripts resolve identifiers, branch names, work-item folders, and the work-folder tier. A caller that needs one of those reads its contract there rather than here, so a caller that only writes a working file never loads it. ADR 003 and ADR 004 carry the design rationale for all of them.
