---
name: auto-number
user-invocable: false
description: Reusable file sequence numbering with prefix (NNNN-name) and suffix (name-NNNN) modes. Returns the next available zero-padded 4-digit number for a given directory.
allowed-tools: Bash(*/skills/auto-number/auto-number.sh *)
---

# Auto-Number

Returns the next available 4-digit sequence number for files in a directory. Run the script and use its stdout directly -- do not reimplement the numbering logic.

## Usage

```bash
skills/auto-number/auto-number.sh <directory> <mode> [glob_pattern]
```

**Arguments:**

- `directory` (required) -- path to scan for existing numbered files
- `mode` (required) -- `prefix` for `NNNN-name.ext` or `suffix` for `name-NNNN.ext`
- `glob_pattern` (optional) -- file filter (e.g., `*.txt`); omit to scan all files

**Output:** A single line with the next NNNN (e.g., `0001`, `0042`).

## Examples

```bash
# Next prefix number in .commit-msgs/issues/5/
skills/auto-number/auto-number.sh .commit-msgs/issues/5 prefix

# Next suffix number, only counting .json files
skills/auto-number/auto-number.sh some/dir suffix "*.json"
```

## Behavior

- Starts at `0001` if the directory is empty or has no matching files
- Finds the highest existing number and returns max + 1
- Gaps are preserved (0001, 0005 → next is 0006, not 0002)
- Non-matching filenames are ignored
