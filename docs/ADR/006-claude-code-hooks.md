# ADR 006: One Session per Work Folder, and a Claude Code Hook

- **Status:** Accepted
- **Date:** 2026-10-18
- **Issues:** <https://github.com/couimet/my-claude-skills/issues/292>, <https://github.com/couimet/my-claude-skills/issues/295>, <https://github.com/couimet/my-claude-skills/issues/296>
- **Amended:** 2026-10-21 by <https://github.com/couimet/my-claude-skills/issues/302> (the `gone` state); 2026-10-28 by <https://github.com/couimet/my-claude-skills/issues/306> (the `UserPromptSubmit` event, and the caller as a holder)

## Context

This ADR amends three decisions of ADR 003: "Identity is the session, never the process", "Every refusal falls back rather than failing", and "Nothing prunes old session files". Each of those sections points here.

A session writes its working files to the folder that its session file names (ADR 003). Three facts broke that rule in real use:

- A `/clear` gives a session a new session id, and its session file keeps the name of the old one. The readers looked for a file under the new id, found none, and used the default folder with no warning.
- `resume-agent.sh` decided that a session runs when any row of `claude agents --json` had its session id. A row with no process looked live, and a session after a `/clear` looked ended, so the script could start a copy of a running session.
- Nothing stopped a second session from claiming a folder that a session already held.

The skills see only the session starts that they make. A manual `claude --bg --resume`, a resume from the agent view, a wake that Claude Code makes by itself, and a `/clear` in an interactive session go through no skill. Only a Claude Code hook sees each start. The "skill hooks" of ADR 001 are a different thing: a `<skill>-hook` skill that a project supplies.

## Probe results

Each probe ran on Claude Code 2.1.302, on 2026-10-18, with sessions that the probe started and then stopped and removed. A logging hook came from `claude --settings <temporary file>` or `claude --plugin-dir <temporary plugin>`, so no user settings file changed.

### The job record, the session ids, and the start directory

- After a `/clear`, the job state (`$CLAUDE_JOB_DIR/state.json`) keeps the first session id in `sessionId` and holds the new id in `resumeSessionId`. The row in `claude agents --json` keeps its 8-character job id, the first 8 characters of the first session id, and shows the new id in `sessionId`. An ended row in `--all` shows the first session id.
- `claude --bg --resume <first session id>` wakes the same job record, in the launch directory of the job, and continues the newest conversation. The shell directory and a Bash `cd` in the session have no effect.
- `claude --bg --resume <conversation id>` of a cleared session makes a second job record under the same name, in the shell directory. `claude --bg --resume <8-character job id>` starts a copy.
- A row becomes `retired` (in the live list, `status: null`, `pid: null`) when the process of a background session dies while the session waits for the user. The daemon woke such a probe row by itself within about 10 seconds. Older `retired` rows on the same machine stayed `retired` for days, for a reason the probe did not find. `claude attach <job id>` wakes a `retired` row with one record. `claude --bg --resume <full session id>` of it starts a copy.
- `claude rm <job id>` deletes the job record and its worktree, and keeps the transcript.

### The hook events

1. **A value that crosses a `/clear`.** In an interactive session and in a background session, `/clear` fires `SessionEnd` with `reason: clear` and the old id, then `SessionStart` with `source: clear` and the new id, about one second later. `CLAUDE_PID` is the same in both calls, and `CLAUDE_CODE_SESSION_ID` in each call is the `session_id` of its input. A background session also has the same `CLAUDE_JOB_DIR` in both calls.
2. **`SessionStart` with `source: resume`.** It fires for `claude --bg --resume`, for a wake through `claude attach` of a stopped job, and for a wake that the daemon makes by itself. A resume from the agent view was not tested, because it needs a person. The job record keeps `--settings` in its `respawnFlags`, so a hook from a settings flag also runs on a wake.
3. **`additionalContext` on a resume with no prompt.** The model of the resumed session read the text and gave it back in its first reply.
4. **A plugin hook in a subfolder.** A `SessionStart` hook from the `hooks/hooks.json` of a plugin ran in a session that started in a subfolder of a repository, with `CLAUDE_PLUGIN_ROOT` set.

A `matcher` filters both events: `SessionStart` with `clear|resume` and `SessionEnd` with `clear` did not run at `startup` or at the exit of a session.

### The session title (Claude Code 2.1.312, 2026-10-28)

Two background sessions ran with `claude --bg --settings <temporary file>`, and the probe then stopped and removed them.

1. **`hookSpecificOutput.sessionTitle` from `UserPromptSubmit`.** The hooks documentation does not list the field. It changed the shown title, the `name` of `claude agents --json`, and the `name` of the job state. A `SendMessage` to the new name reached the session.
2. **The `session_title` input.** It held the `--name` value at the first prompt, the title that the hook set at the next prompt, and `null` in a session with no title yet.
3. **The transcript.** A title that the hook set wrote `custom-title` entries, the entry type of a typed `/rename`. An AI title wrote `ai-title` entries. So only a record of the hook tells its own title from a choice of the user.
4. **AI titles.** A session with a `SessionStart` command hook (matcher `clear|resume`) still got an AI title. A report that a `SessionStart` hook stops AI titles on 2.1.252 does not apply to 2.1.312.
5. **Cross-session messages.** `UserPromptSubmit` also fired for a prompt that arrived as a cross-session message.

## Decision

### One rule for the state of a session

`skills/issue-context/folder-sessions.sh` is the one rule that says which sessions claim a folder and whether each one runs: `running`, `retired`, or `ended`. It joins the session files to `claude agents --json` and `--json --all` by session id, by job id, and by the new `job_session_id` field of a session file, so the files of one job, before and after a `/clear`, give one line. `resume-agent.sh`, `launch-agent.sh`, and `set-work-folder.sh` call it, and a caller in another repository calls it too.

> **Amended by [issue 302](https://github.com/couimet/my-claude-skills/issues/302).** A fourth state, `gone`, splits `ended`. A session with no live row is `gone` when Claude Code deleted the transcript of the conversation that a resume loads: the `resumeSessionId` of its job record, else its session id. A resume of it gives an empty conversation with no history and no name. `resume-agent.sh` stops on it with R008 and does not fall back to an older session, and `launch-agent.sh` gives it no `/resume-agent` hint. A missing transcript directory is H005, not `gone`. A `running` or a `retired` session gets no transcript check.

### The reader falls back to the first id of the job

When no session file names the live id, the reader of `session-file.sh` uses the files of the first session id in the job state. This covers a background session after a `/clear` with no hook.

### One session for each folder

`set-work-folder.sh` and `launch-agent.sh` refuse a folder that another `running` or `retired` session holds. The error names that session and the `/resume-agent` command that continues it. `--take-over` removes the session files of the other session and prints its `claude stop` command. It never stops that session, because a stop can cut a turn in progress. With `--bg`, the caller counts as a holder. When the check cannot run, the claim goes on with one warning line, because a refusal would send the working files to the default folder with no sign.

### `resume-agent.sh` follows the probes

It resumes the first session id of an ended job, in the launch directory of the job. It restarts nothing for a `retired` session and prints the `claude attach` command.

### The hook

One script handles three events:

- **`SessionEnd`, matcher `clear`:** read the folder of the old id, and write it to a handoff file named after `CLAUDE_PID` (probe 1).
- **`SessionStart`, matcher `clear`:** when no session file names the new id, take the folder from the handoff file, or else from the job state, and write the session file of the new id with `set-work-folder.sh`. This covers an interactive session, which has no job state.
- **`SessionStart`, matcher `resume`:** when `folder-sessions.sh` shows another `running` or `retired` session in the folder, return `additionalContext` that names it, tells the session not to write in the folder, and gives the `/resume-agent` command (probes 2 and 3).

The hook never stops a start: on any error it exits 0 and prints at most one stderr line. It is idempotent, because a user can install it through the plugin and through the settings file. It lives in a skill folder, so `install.sh`, the skills CLI, and the plugin all ship it. The plugin names it in `hooks/hooks.json` (probe 4). `install.sh` checks that the script of the entry can run, asks before it adds the same entry to `~/.claude/settings.json`, keeps a backup, honors `--no-hooks`, and removes the entry on uninstall. The README gives the entry for a user of the skills CLI.

No probe failed, so the hook keeps both gaps of issue 296.

> **Amended by [issue 306](https://github.com/couimet/my-claude-skills/issues/306).** A fourth event, **`UserPromptSubmit`** with no matcher, keeps the session name equal to the folder name of its work folder (title probes 1 to 5). A send by name and the agent view find a session by that name. The hook keeps a title record for each session, `<dirname SETTINGS_FILE>/session-titles/<session id>.json`, with the last title that it set, the last title that it warned about, and the name that `/rename-agent` asked for. After a drift (no title, or a newest `ai-title` entry), the hook sets the folder name. When another `running` or `retired` session holds the folder, it warns instead, because two sessions with one name make a send by name ambiguous. A title that the user chose stays, and the hook warns once for each such title with the line of `find-agent.sh --check`: `/launch-agent <that folder>` first when the title is the folder name of another existing folder, `/rename-agent` first otherwise. A name from `/rename-agent` applies with no warning. A `/clear` moves the title record to the new id with the folder. The first checks read only the session file and the input, because this event runs at each prompt. `skills/issue-context/find-agent.sh` gives the verdict of a folder or of a session, and `launch-agent.sh` (L007) and `resume-agent.sh` (R003) take their advice from it.
>
> `resume-agent.sh` also stops with R009 when the session file of the caller names the folder and the chosen session ended. `/launch-agent` binds the caller to a folder whose session ended and hints at `/resume-agent`, so the premise "it wakes the session that holds the folder" fails: the caller holds the folder too. No time rule replaces the check, because a `/clear` writes the session file again.

## Consequences

### Positive

- A background session keeps its work folder after a `/clear` now, with or without a hook.
- No caller keeps its own copy of the liveness rule.
- A second session cannot claim a held folder through the skills, and a person who wants it anyway has one explicit override.

### Negative

- The rule reads the job state of Claude Code (`state.json`), which is not a documented interface. A change of its shape makes the fallback find nothing, never something wrong.
- The hook runs in each session of each user. Its matchers keep it out of each start and end that is not a `/clear` or a resume. Since [issue 306](https://github.com/couimet/my-claude-skills/issues/306), it also runs at each prompt, with no matcher. A session with no session file, or with a title equal to its folder name, costs one parse and one session file read.
- A user who installs both the plugin and the settings entry runs the hook twice. The hook is idempotent, so the cost is time only.

## Alternatives Considered

### No hook (rejected)

The reader fallback covers only a background session, and the guard covers only the starts that the skills make. The probes show that a hook covers both gaps.

### A hook that renames a restarted session (rejected)

On Claude Code 2.1.299, a `SessionStart` hook that returns `sessionTitle` did not rename a background session in the agent view. `resume-agent.sh` prints a `Rename:` line instead.

> **Amended by [issue 306](https://github.com/couimet/my-claude-skills/issues/306).** A `UserPromptSubmit` hook can set the title on 2.1.312 (title probe 1). So the hook now restores the folder name at the next prompt, and `/rename-agent` asks for a name through it. The restart of `resume-agent.sh` keeps its `/rename` prompt, because a restarted session gets no prompt from the user until the person sends one.
