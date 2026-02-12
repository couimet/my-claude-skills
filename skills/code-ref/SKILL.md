---
name: code-ref
user-invocable: false
description: Defines the format for code references in working documents (scratchpads, plans, questions, commit messages). Auto-consulted when generating file/line references. Uses GitHub-style permalink syntax that becomes clickable navigation when RangeLink or similar tools are installed.
---

# Code References

When referencing code locations in working documents, use GitHub-style permalink syntax. These references become clickable navigation links when tools like RangeLink are installed.

## Format

| Reference Type | Syntax | Example |
|---|---|---|
| Single line | `path/to/file.ts#L10` | src/parser.ts#L42 |
| Line range | `path/to/file.ts#L10-L20` | src/parser.ts#L42-L58 |
| Character precision | `path/to/file.ts#L10C5-L20C15` | src/parser.ts#L42C3-L42C28 |

## Rules

1. **Workspace-relative paths** — always from the project root, never absolute paths
2. **Never wrap in backticks** — backticks become part of the parsed path and break link navigation
3. **Never use plain text references** — "lines 26-37", "Line 539", "(L42-L58)" are not parseable

## Bad Examples

- file.ts (lines 26-37)
- Line 539 mentions "TextInserter"
- `src/parser.ts#L26-L37` (backticks break the link)
- /Users/name/project/src/parser.ts#L26 (absolute path)

## Good Examples

- src/parser.ts#L26-L37
- src/parser.ts#L539 mentions "TextInserter"
- Remove the standalone logging tests at src/utils/__tests__/helper.test.ts#L54-L85
- The validation logic at src/validator.ts#L12C5-L12C42 should use strict equality
