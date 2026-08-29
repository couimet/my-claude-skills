---
name: concise-output
description: 'Conciseness rules for generated files and console text. Invokes the external /asd-ste100 skill (Simplified Technical English) when available. Applies a condensed built-in fallback when it is not. Auto-consulted when a skill writes file content. Invoke directly to condense any text.'
argument-hint: <text>
user-invocable: true
allowed-tools:
---

# Concise Output

Conciseness rules for skill-generated text and for console text the user asks to condense. Consulted automatically by content-producing skills through `/prose-style`. Invoked directly with `/concise-output <text>` to rewrite any text in the console.

## When to apply

Apply the pass to prose regions in every file a skill produces: notes, scratchpads, questions, commit messages, PR descriptions, changelogs, breadcrumbs, and article drafts. Preserve YAML front matter, fenced code blocks (including scratchpad JSON step blocks), shell commands, URLs, and required exact-match strings. Use STE-flavored mode: concise and unambiguous, but not a personality transplant. Preserve every fact, every condition, and every hedge. Never add a claim the source did not make.

When invoked directly, rewrite the given text with the pass and print only the rewritten text. Suppress any `Kept as-is:` line the external skill appends. Do not write a file and do not add a preamble.

Auto-consult descriptions (prose-style, note, concise-output) may exceed the 25-word cap. They keep the trigger phrases that load the pass.

## Invocation

Reference `/asd-ste100` for the full treatment. When that skill resolves, apply its STE-flavored rules: structural rules in full, lexical rules as a direction of travel.

## Graceful degradation

If `/asd-ste100` is not installed, or is installed but cannot load or invoke, apply these condensed fallback rules instead:

1. Use the active voice. "The agent deletes the file." not "The file is deleted by the agent."
2. Keep each sentence at or below 25 words, one idea per sentence.
3. No semicolons and no phrasal verbs. "Remove the panel." not "Take off the panel."
4. Use one name for each thing, every time. Do not rotate synonyms for the same idea.
5. Cut filler and marketing adjectives. Replace or delete "in order to", "due to the fact that", "seamless", "robust".
6. Keep every fact and every hedge. "The request may have failed." stays "may have failed". Never promote a hedge to a fact.

## Self-check before you finish

Re-check the output before sending it. Flag every violation of the rules above and fix it. If the text already complies, leave it alone.
