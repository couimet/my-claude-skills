---
name: issue-context
user-invocable: false
description: Detects issue context from git branch name and determines subdirectory organization for working files. Auto-consulted by foundation skills (/scratchpad, /question, /commit-msg, /breadcrumb) when deciding where to place files.
allowed-tools: Read, Write, Bash(git branch --show-current), Bash(*/skills/auto-number/auto-number.sh *), Glob
---

# Issue Context

Determines file placement based on the current git branch. Foundation skills consult this to organize working files into issue-scoped subdirectories.

## Branch Detection

Read the current branch:

```bash
git branch --show-current
```

### Extracting the Issue ID

The branch must start with `issues/`. The segment after `issues/` is parsed to extract the ID.

**Rule**: Split on the first `-` or `_` only if the characters before it are purely numeric. Otherwise, the full segment is the ID.

Examples:

- `issues/332` → `332`
- `issues/332-convert-commands` → `332`
- `issues/332_convert_commands` → `332`
- `issues/rangelink-332` → `rangelink-332` (not purely numeric before `-`)
- `issues/v2-hotfix` → `v2-hotfix` (not purely numeric before `-`)

### No Issue Context

These branch patterns produce no issue context — files use flat root placement:

- `main`, `master`
- `side-quest/*`
- `feature/*`, `fix/*`
- Any branch not starting with `issues/`

## File Placement

Foundation skills (scratchpad, question, commit-msg) use this to determine the target directory:

### When issue context is detected

Files go in an issue-scoped subdirectory:

```
<root>/issues/<ID>/NNNN-description.txt
```

Where `<root>` is the skill's base directory (`.scratchpads/`, `.claude-questions/`, `.commit-msgs/`).

- Create the `issues/<ID>/` subdirectory if it doesn't exist
- The `NNNN` file sequence number is scoped to this subdirectory (each issue starts fresh at `0001`)

Examples:
- `.scratchpads/issues/332/0001-implementation-plan.txt`
- `.claude-questions/issues/332/0001-api-design.txt`
- `.commit-msgs/issues/332/0001-add-parser.txt`

### When no issue context

Files go directly in the root directory with global numbering:

```
<root>/NNNN-description.txt
```

- The `NNNN` file sequence number is global across all files in the root directory

Examples:
- `.scratchpads/0042-refactoring-analysis.txt`
- `.claude-questions/0003-architecture-options.txt`

## Auto-Numbering (`NNNN`)

The `NNNN` file sequence number is always scoped to the target directory. Use `/auto-number` to get the next number -- do not reimplement the algorithm.

1. Determine the target directory using the File Placement rules above
2. Run `/auto-number` against that directory:
   ```bash
   skills/auto-number/auto-number.sh <target-directory> --glob "*.txt" --width 4
   ```
3. Use the script's stdout as the `NNNN` value

## Breadcrumbs

Breadcrumbs use a different pattern — a single file per issue rather than numbered files:

```
.breadcrumbs/<ID>.md
```

The `/breadcrumb` skill handles this directly, but still uses issue-context for branch detection and ID extraction.

## Ensure `.gitignore`

Foundation skills already consult issue-context for directory placement — this check runs as part of that same consultation. Before creating any ephemeral file, ensure the project's `.gitignore` includes entries for all skill working directories. This prevents SCM noise in consuming projects.

1. Read `.gitignore` in the project root (if it doesn't exist, treat contents as empty)
2. Check if the sentinel comment `# Claude skill working directories` is present
3. If **already present** → do nothing (idempotent)
4. If **missing** → append the following block (with a leading blank line if the file is non-empty):

```text
# Claude skill working directories
.scratchpads/
.claude-questions/
.commit-msgs/
.breadcrumbs/
```

This runs once per project — subsequent skill invocations find the sentinel and skip.
