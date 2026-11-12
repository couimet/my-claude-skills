---
name: save-prompt
version: 2026.11.11.1@0054246
description: Save a prompt verbatim in the prompts/ folder of the work folder, read from the session transcript so no model copies the text. Use when the user says "save this prompt verbatim", "save the prompt", or "keep this prompt".
argument-hint: '[--kind launch|next|saved]'
allowed-tools: Bash(*/skills/save-prompt/save-prompt.sh *)
---

# Save Prompt

Save a prompt of the user in the work folder, byte for byte. The script reads the text from the transcript of this session. **Never copy the text yourself, and never write the file with another tool:** a model copy can change the text.

**Input:** $ARGUMENTS (an optional `--kind launch|next|saved`; the default is `saved`)

## When to Use

Use it only when the user asks to keep a prompt, such as "save this prompt verbatim", or with a bare `/save-prompt` after a long prompt. A launch or a resume of a session never calls it.

The kinds:

- `saved`: a prompt that the user keeps. No session runs it. The default.
- `next`: a prompt that a session runs later, such as after a `/clear`.
- `launch`: a prompt that starts or relaunches a session of the folder. `/launch-agent` saves its own prompt, so use it only when the user asks for this kind.

## Step 1: Run the Script

```bash
~/.claude/skills/save-prompt/save-prompt.sh --kind "<kind>"
```

The script saves the human message of the current turn. When that message is a bare `/save-prompt`, it saves the human message before it. A message that the user sent while the turn ran follows the saved text under a separator line. A message that arrives after the script runs is not in the file: run the skill again to add it. The script header gives each rule.

The file is `<work folder>/prompts/<YYYYMMDD-HHMMSS>-<kind>.txt`. The script reads the work folder from the session file of this session.

## Step 2: Report

Give the user the absolute path that the script printed, or its `Repeat:` line: a repeat of the newest file of the same kind writes nothing. An error names its code. M003 means that this session has no work folder: give the user the error, which names `/set-work-folder`. M005 means that the transcript holds no human message, and the transcript form can have changed.

## Hook Points

A project adds its own steps in a hook skill, `/save-prompt-hook`. See `/skill-hooks`. The hook can only add requirements, at one point:

1. **After-save steps** (after Step 2): bookkeeping after the write, such as a step in the project's own tracker that names a `next` prompt. The hook gets the kind and the absolute path of the file. A `Repeat:` result wrote nothing, so it has no after-save steps.

When no hook exists, the skill ends after Step 2.

## Formatting

See `/prose-style` for hard-wrap and reference rules.
