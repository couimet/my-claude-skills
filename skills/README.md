# Skills

## Foundation Skills (standalone workflow primitives)

| Skill | Invocation | What It Does |
| --- | --- | --- |
| `note` | `/note <desc>` | Creates `.claude-work/notes/YYYYMMDD-HHMMSS-slug.txt` — lightweight capture; default working-document type for composite skills |
| `scratchpad` | `/scratchpad <desc>` | Creates `.claude-work/scratchpads/NNNN-description.txt` with auto-numbering and a JSON step block; opt-in when composite skills need formal step tracking via `/tackle-scratchpad-block` |
| `question` | `/question <topic>` | Creates `.claude-work/questions/NNNN-topic.txt` for user Q&A |
| `changelog` | `/changelog <desc>` | Creates or updates a CHANGELOG entry with tone guardrails, thematic grouping, and detail-leak detection |
| `commit-msg` | `/commit-msg <desc>` | Creates `.claude-work/commit-msgs/NNNN-description.txt` |
| `breadcrumb` | `/breadcrumb <note>` | Appends timestamped note to `.claude-work/issues/<ID>/breadcrumb.md` |

## Non-Invocable Skills

Non-invocable skills (`user-invocable: false`) don't appear in the `/` menu. They load into Claude's context two different ways, so the table below splits them by mechanism.

### Auto-consulted skills (description matches task → body loads as context)

| Skill | Purpose |
| --- | --- |
| `/file-placement` | Decision tree for where to put different file types. Claude auto-consults when deciding output locations. |
| `/label-discovery` | Fetches GitHub labels, classifies them as defaults vs structured, and prompts the user for selection. Auto-consulted by `/create-github-issue`. |
| `/prose-style` | Canonical prose and reference formatting rules — hard-wrap rule, code-reference syntax, GitHub-reference syntax. Auto-consulted whenever a skill produces file content. |
| `/scratchpad-ref-format` | Defines the 4 invocation forms for referencing scratchpad steps (`#S`, `#L`, space-separated, bare-path auto-select). Auto-consulted by `/tackle-scratchpad-block` when parsing its argument. |

### Script-backed / reference-only skills (invoked via Bash or referenced by explicit contract)

| Skill | Purpose |
| --- | --- |
| `/auto-number` | Reusable file sequence numbering with prefix (`NNNN-name`) and suffix (`name-NNNN`) modes. Called by `target-path.sh` and directly by skills that need the next number in a directory. |
| `/ensure-gitignore` | Checks that `.gitignore` contains the Claude working directory sentinel and appends it if missing. One Bash call — no file contents loaded into context. Called directly by `/question`, `/scratchpad`, `/commit-msg`. |
| `/issue-context` | Thin pointer skill for `target-path.sh` — the shell script that resolves `.claude-work/` file paths from the current git branch. Not auto-consulted; referenced by contract. |

## Composite Skills (higher-level workflows)

| Skill | Invocation | Foundation Dependencies |
| --- | --- | --- |
| `cleanup-issue` | `/cleanup-issue [number]` | (inline branch parsing) |
| `create-github-issue` | `/create-github-issue <title-or-path>` | `/scratchpad` (reads), `/question`, `/label-discovery` |
| `finish-issue` | `/finish-issue` | `/note` (default), `/scratchpad` (opt-in, reads), `/question`, breadcrumbs (reads); handles both `issues/*` and `side-quest/*` branches |
| `start-issue` | `/start-issue <url> [--scratchpad]` | `/note` (default), `/scratchpad` (opt-in), `/question`, `/cleanup-issue` |
| `start-side-quest` | `/start-side-quest <desc> [--scratchpad]` | `/note` (default), `/scratchpad` (opt-in), `/question`, `/commit-msg` (ref) |
| `tackle-pr-comment` | `/tackle-pr-comment <url> [--scratchpad]` | `/note` (default), `/scratchpad` (opt-in), `/question`, `/commit-msg` |
| `tackle-scratchpad-block` | `/tackle-scratchpad-block <path#lines>` | `/scratchpad-ref-format`, `/question`, `/commit-msg`, `/scratchpad` (reads) |

## Architecture

**Default working document: `/note`, with `/scratchpad` as an explicit opt-in.** Composite skills (`/start-issue`, `/start-side-quest`, `/tackle-pr-comment`, `/finish-issue`) default to creating a `/note` for their working document. The premise is that LLMs are strong enough at self-organizing tasks in-session (via TaskCreate/TaskUpdate) that the structured scratchpad + `/tackle-scratchpad-block` chain is best reserved for cases where the user explicitly wants formal step tracking. Users opt in via `--scratchpad` on the skill invocation or equivalent natural-language triggers ("use a scratchpad", "with step tracking", "formal plan"). Whichever type is produced, `/start-issue` and `/start-side-quest` also write an active-plan pointer (`.claude-work/issues/<ID>/active-plan` or `.claude-work/active-plan-<slug>`) so `/finish-issue` and `/tackle-scratchpad-block` can resolve the primary plan unambiguously without globbing.

**Two-tier design:** Foundation skills define standalone conventions (file formats, numbering, placement rules). Composite skills orchestrate workflows by referencing foundations by name. In rare cases where a composite needs only a two-line foundation detail, it may deliberately inline that rule rather than cross-reference — the current example is `/cleanup-issue`, which inlines the branch-parsing rule instead of pulling in a foundation for it.

**Non-invocable skills** (`user-invocable: false`) don't appear in the `/` menu but their descriptions load into Claude's context. Claude auto-consults them when the context matches (e.g., generating code references, deciding where to put files).

**Script-backed skills:** When a skill's logic is purely deterministic (no judgment calls, no context-dependent decisions), a Bash script is more token-efficient than inline markdown instructions. Most skills describe an algorithm in Markdown and let Claude reason through it each invocation. That works well for complex decisions but wastes tokens on deterministic logic. A script executes in one Bash call and returns a single line of stdout — Claude spends zero tokens on the algorithm itself.

Three scripts follow this pattern. `auto-number` handles "scan directory, find max number, add 1, zero-pad" — purely mechanical, runs on every `/scratchpad`, `/commit-msg`, and `/question` invocation. `ensure-gitignore` handles its read-check-append operation before creating any file. `target-path.sh` (in `skills/issue-context/`) combines branch detection, issue-ID extraction, slug normalization, and auto-numbering into one call and is the sole path-resolver for `/scratchpad`, `/question`, and `/commit-msg`. All three return a single line of output and let Claude focus on decisions only it can make.

## Step Tracking

Step tracking applies only to the `/scratchpad` opt-in path. When a scratchpad contains an implementation plan, its steps are embedded as a fenced JSON block inside the `## Implementation Plan` section. Each step has:

- **`id`** — `S001`, `S002`, etc. (zero-padded 3-digit, mirrors Q001/A001)
- **`status`** — `pending` | `in_progress` | `done` | `blocked`
- **`done_when`** — concrete completion criteria (optional)
- **`depends_on`** — array of step IDs that must be done first
- **`files`** / **`tasks`** — what to touch and what to do

When the opt-in scratchpad path is taken, planning skills (`/start-issue`, `/start-side-quest`, `/tackle-pr-comment`) always write `"status": "pending"`. The `/tackle-scratchpad-block` skill manages status transitions during execution. See the `/scratchpad` skill for the full JSON schema. On the default note path, there is no JSON block; the LLM self-organizes using its in-session task tracking.
