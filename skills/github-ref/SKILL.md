---
name: github-ref
version: 2026.03.19@26f93d6
user-invocable: false
description: Defines the rule for GitHub references in working documents. Auto-consulted when any skill produces text containing issue or PR references.
---

# GitHub References

When generating text files, always use full GitHub URLs for issue and PR references. Short-form references are ambiguous across repositories.

## Rule

Never use `#NNN`, `PR #NNN`, or `issue #NNN` in any skill-generated output. Always use the full URL.

| Reference type | Full URL format |
| --- | --- |
| Issue | `https://github.com/{owner}/{repo}/issues/{number}` |
| Pull request | `https://github.com/{owner}/{repo}/pull/{number}` |

## Bad Examples

- `#749`
- `PR #136304`
- `issue #10953`
- `See PR #139251 for details`
- `Closes #25`

## Good Examples

- `https://github.com/couimet/my-claude-skills/issues/25`
- `https://github.com/couimet/my-claude-skills/pull/28`
- `See https://github.com/couimet/my-claude-skills/pull/28 for details`
- `Closes https://github.com/couimet/my-claude-skills/issues/25`

## URL Construction

**When the full URL is already available** (e.g., from skill input like `/start-issue https://github.com/org/repo/issues/42`): use it directly. Never shorten a full URL to a short reference.

**When the repo is implicit** (e.g., self-referential, current working repo): construct the URL from the known remote:

```bash
gh repo view --json url -q .url
# → https://github.com/couimet/my-claude-skills
```

Then append `/issues/{number}` or `/pull/{number}` as appropriate.

**When the number is in context but the URL is not** (e.g., a commit message referencing the current branch's issue): use `gh repo view` to build the URL rather than writing `#NNN`.
