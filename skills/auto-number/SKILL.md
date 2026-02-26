---
name: auto-number
version: 2026.02.25@abc1234
user-invocable: false
description: Reusable file sequence numbering with prefix (NNNN-name) and suffix (name-NNNN) modes. Returns the next available zero-padded sequence number for a given directory.
allowed-tools: Bash(*/skills/auto-number/auto-number.sh *)
---

# Auto-Number

Returns the next available sequence number for files in a directory. Run the script and use its stdout directly -- do not reimplement the numbering logic.

## Usage

```bash
skills/auto-number/auto-number.sh <directory> [--mode prefix|suffix] [--glob PATTERN] [--width N]
```

**Arguments:**

- `directory` (required, positional) -- path to scan for existing numbered files
- `--mode` (optional) -- `prefix` for `NNNN-name.ext` or `suffix` for `name-NNNN.ext`. Default: `prefix`
- `--glob` (optional) -- file filter pattern (e.g., `*.txt`). Default: all files
- `--width` (optional) -- output width, 1-10. Default: 4. Safety: never truncates if next value needs more digits

**Output:** A single line with the next number, zero-padded to width (e.g., `0001` at default width, or `000042` with `--width 6`).

## Examples

```bash
# Next prefix number in .claude-work/issues/5/commit-msgs/ (default mode, default width)
skills/auto-number/auto-number.sh .claude-work/issues/5/commit-msgs

# Next suffix number, only counting .json files
skills/auto-number/auto-number.sh some/dir --mode suffix --glob "*.json"

# Next number with 6-digit padding
skills/auto-number/auto-number.sh some/dir --width 6
```

## Behavior

- Starts at `0001` (at default width) if the directory is empty or has no matching files
- Finds the highest existing number and returns max + 1
- Gaps are preserved (0001, 0005 → next is 0006, not 0002)
- Non-matching filenames are ignored
- Suffix mode strips only the last extension (e.g., `report-0042.tar.gz` becomes `report-0042.tar`), so files with compound extensions are silently skipped
- Width is a minimum -- if the next value needs more digits than requested, the output expands (e.g., `--width 3` with max 999 outputs `1000`)

## Design

This skill uses a Bash script instead of inline SKILL.md instructions. Most skills describe an algorithm in Markdown and let Claude reason through it each invocation. That works well for complex decisions but wastes tokens on deterministic logic like "scan directory, find max number, add 1, zero-pad." The script executes in one Bash call and returns a single line of stdout -- Claude spends zero tokens on the algorithm itself. This matters because auto-numbering runs on every `/scratchpad`, `/commit-msg`, and `/question` invocation.

## Error Codes

All errors exit 1 with a message on stderr in the format `auto-number EXXX error: <details>`. Codes use two ranges: E0xx for generic errors (missing required arguments, unknown flags) and E1xx for parameter validation (invalid values, directory problems).

- **E001** -- missing directory argument
- **E002** -- unknown flag or unexpected argument
- **E100** -- invalid mode (not `prefix` or `suffix`)
- **E101** -- invalid width (not an integer 1-10)
- **E102** -- directory does not exist
- **E103** -- path is not a directory
- **E104** -- directory not readable
- **E105** -- missing value for `--glob`
