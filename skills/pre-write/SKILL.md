---
name: pre-write
version: 2026.06.07@5ceb5b6
description: Think-before-writing rule for content-generating skills. Complete all reasoning before producing any file content. Auto-consulted before any skill writes file content.
user-invocable: false
allowed-tools:
---

# Pre-Write

**Consulted automatically by content-generating skills. Not invoked directly by the user.**

## Think before writing

Complete all context-gathering and reasoning before producing any file content. The file must reflect finished thinking, not in-progress deliberation.

Phrases like "oh wait," "I now realize," "actually," "hmm," or any mid-stream self-correction in a generated file are signals that writing started too early. They must not appear in generated files.

If context is incomplete — or if a decision would benefit from user input — stop and use `/question` before proceeding. Never embed uncertainty or evolving reasoning in the generated file.

The test: can you state the full shape of the output before writing the first word? If not, gather more context first.
