# Skills

## Foundation Skills (standalone workflow primitives)

| Skill | Invocation | What It Does |
| --- | --- | --- |
| `scratchpad` | `/scratchpad <desc>` | Creates `.claude-work/scratchpads/NNNN-description.txt` with auto-numbering |
| `question` | `/question <topic>` | Creates `.claude-work/questions/NNNN-topic.txt` for user Q&A |
| `commit-msg` | `/commit-msg <desc>` | Creates `.claude-work/commit-msgs/NNNN-description.txt` |
| `breadcrumb` | `/breadcrumb <note>` | Appends timestamped note to `.claude-work/issues/<ID>/breadcrumb.md` |

## Non-Invocable Skills (auto-consulted by Claude)

| Skill | Purpose |
| --- | --- |
| `auto-number` | Reusable file sequence numbering with prefix (`NNNN-name`) and suffix (`name-NNNN`) modes. Auto-consulted by `/issue-context` and available for direct use by other skills. |
| `code-ref` | Defines permalink format for code references (`path/to/file.ts#L10-L20`). Claude auto-consults when generating file/line references. |
| `ensure-gitignore` | Checks that `.gitignore` contains the Claude working directory sentinel and appends it if missing. One Bash call — no file contents loaded into context. Auto-consulted by `/issue-context`. |
| `file-placement` | Decision tree for where to put different file types. Claude auto-consults when deciding output locations. |
| `issue-context` | Detects issue context from git branch name, determines subdirectory organization and `NNNN` file numbering. Claude auto-consults when foundation skills need directory placement. |
| `scratchpad-ref-format` | Defines the 4 invocation forms for referencing scratchpad steps (`#S`, `#L`, space-separated, bare-path auto-select). Auto-consulted by `/tackle-scratchpad-block` when parsing its argument. |

## Composite Skills (higher-level workflows)

| Skill | Invocation | Foundation Dependencies |
| --- | --- | --- |
| `audit-efficiency` | `/audit-efficiency [skills-dir]` | Read, Glob, Grep |
| `cleanup-issue` | `/cleanup-issue [number]` | `/issue-context` |
| `create-github-issue` | `/create-github-issue <title-or-path>` | `/scratchpad` (reads), `/question` |
| `finish-issue` | `/finish-issue` | `/scratchpad` (reads), `/question`, breadcrumbs (reads); handles both `issues/*` and `side-quest/*` branches |
| `start-issue` | `/start-issue <url>` | `/scratchpad`, `/question`, `/cleanup-issue` |
| `start-side-quest` | `/start-side-quest <desc>` | `/scratchpad`, `/question`, `/commit-msg` (ref) |
| `tackle-pr-comment` | `/tackle-pr-comment <url>` | `/scratchpad`, `/question`, `/commit-msg` |
| `tackle-scratchpad-block` | `/tackle-scratchpad-block <path#lines>` | `/scratchpad-ref-format`, `/question`, `/commit-msg`, `/scratchpad` (reads) |

## Architecture

**Two-tier design:** Foundation skills define standalone conventions (file formats, numbering, placement rules). Composite skills orchestrate workflows by referencing foundations by name — they never inline foundation definitions.

**Non-invocable skills** (`user-invocable: false`) don't appear in the `/` menu but their descriptions load into Claude's context. Claude auto-consults them when the context matches (e.g., generating code references, deciding where to put files).

**Script-backed skills:** When a skill's logic is purely deterministic (no judgment calls, no context-dependent decisions), a Bash script is more token-efficient than inline markdown instructions. Claude executes one Bash call instead of reasoning through the algorithm each time. `auto-number` and `ensure-gitignore` use this pattern — see their `## Design` sections for the rationale.

## Step Tracking

Implementation plan steps are embedded as a fenced JSON block inside the scratchpad's `## Implementation Plan` section. Each step has:

- **`id`** — `S001`, `S002`, etc. (zero-padded 3-digit, mirrors Q001/A001)
- **`status`** — `pending` | `in_progress` | `done` | `blocked`
- **`done_when`** — concrete completion criteria (optional)
- **`depends_on`** — array of step IDs that must be done first
- **`files`** / **`tasks`** — what to touch and what to do

Planning skills (`/start-issue`, `/tackle-pr-comment`) always write `"status": "pending"`. The `/tackle-scratchpad-block` skill manages status transitions during execution. See the `/scratchpad` skill for the full JSON schema.
