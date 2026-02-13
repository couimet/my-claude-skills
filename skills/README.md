# Skills

## Foundation Skills (standalone workflow primitives)

| Skill | Invocation | What It Does |
| --- | --- | --- |
| `scratchpad` | `/scratchpad <desc>` | Creates `.scratchpads/NNNN-description.txt` with auto-numbering |
| `question` | `/question <topic>` | Creates `.claude-questions/NNNN-topic.txt` for user Q&A |
| `commit-msg` | `/commit-msg <desc>` | Creates `.commit-msgs/NNNN-description.txt` |
| `breadcrumb` | `/breadcrumb <note>` | Appends timestamped note to `.breadcrumbs/<ISSUE>.md` |

## Non-Invocable Skills (auto-consulted by Claude)

| Skill | Purpose |
| --- | --- |
| `code-ref` | Defines permalink format for code references (`path/to/file.ts#L10-L20`). Claude auto-consults when generating file/line references. |
| `file-placement` | Decision tree for where to put different file types. Claude auto-consults when deciding output locations. |
| `issue-context` | Detects issue context from git branch name, determines subdirectory organization and `NNNN` file numbering. Claude auto-consults when foundation skills need directory placement. |

## Composite Skills (higher-level workflows)

| Skill | Invocation | Foundation Dependencies |
| --- | --- | --- |
| `start-issue` | `/start-issue <url>` | `/scratchpad`, `/question` |
| `finish-issue` | `/finish-issue [number]` | `/scratchpad` (reads), `/question`, breadcrumbs (reads) |
| `tackle-scratchpad-block` | `/tackle-scratchpad-block <path#lines>` | `/question`, `/commit-msg`, `/scratchpad` (reads) |
| `start-side-quest` | `/start-side-quest <desc>` | `/scratchpad`, `/question`, `/commit-msg` (ref) |
| `tackle-pr-comment` | `/tackle-pr-comment <url>` | `/scratchpad`, `/question`, `/commit-msg` |

## Architecture

**Two-tier design:** Foundation skills define standalone conventions (file formats, numbering, placement rules). Composite skills orchestrate workflows by referencing foundations by name — they never inline foundation definitions.

**Non-invocable skills** (`user-invocable: false`) don't appear in the `/` menu but their descriptions load into Claude's context. Claude auto-consults them when the context matches (e.g., generating code references, deciding where to put files).
