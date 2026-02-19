# README Design Decisions (Issue #10)

## Q001: Should the root README be the single comprehensive document, or should it stay lean and link to deeper pages?

Context: The current README is 25 lines pointing to skills/README.md. The issue asks to "add meat" — but meat can live in one place or be distributed. This decides the overall information architecture and affects every other question.

Options:
A) Single comprehensive README - Everything in one scrollable document. Beginners don't have to click around. GitHub renders it on the landing page. Downside: could get long (200+ lines).
B) Hub-and-spoke - Root README covers intro, quick start, and philosophy. Link out to skills/README.md for reference and a new docs/workflows.md (or similar) for the advanced scenarios. Keeps each file focused.
C) Progressive disclosure in one file - Comprehensive README but with heavy use of GitHub's `<details>` collapse blocks so the page loads clean and users expand what interests them.

Recommendation: A - A single comprehensive README is the most welcoming. GitHub renders it on the landing page, so visitors see everything without navigating. The content we're planning (intro, quick start, workflow walkthrough, philosophy, reference) is substantial but not unwieldy — probably 300-400 lines. That's normal for a well-documented project. Collapsible sections (option C) can feel clunky and hide value.

A001: [RECOMMENDED] A

---

## Q002: What tone and voice should the README use?

Context: Tone sets the first impression. This is a personal open-source project with real daily use — the voice should reflect that authenticity. It affects how welcoming beginners feel and how seriously advanced users take the content.

Options:
A) Casual and personal - First person ("I built these because..."), conversational, occasional humor. Feels like a blog post or a friend showing you their setup.
B) Professional but warm - Third person or "you"-focused ("These skills help you..."), clean and direct, no jokes but not stiff. Feels like well-written project docs.
C) Tutorial-style - Second person imperative ("Install the skills. Try this command. Notice how..."), teaching tone throughout. Feels like a workshop guide.

Recommendation: A - This is your personal toolkit, battle-tested over many iterations. Casual first-person voice makes it authentic and approachable. It also differentiates it from generic tool documentation — people connect with "here's what I actually use every day" more than impersonal docs.

A002: [RECOMMENDED] A

---

## Q003: How should the "real workflow" scenario be presented?

Context: The scratchpad plan identifies a full issue lifecycle walkthrough as the centerpiece of the README. The issue itself asks for "redacted/safe prompts from my day-to-day." This question decides whether to use fabricated examples or adapt real ones.

Options:
A) Fabricated but realistic - Invent a plausible scenario (e.g., "add CSV export to a reporting tool") and walk through the full lifecycle with made-up but realistic commands and outputs. Easy to control, no redaction needed.
B) Redacted real examples - Take actual prompts and outputs from your daily use, redact proprietary details, and present them. More authentic but requires careful scrubbing.
C) Hybrid - Use a fabricated scenario for the main walkthrough but include a "From My Actual Usage" sidebar or section with short redacted real snippets showing specific moments (a particularly useful breadcrumb, a well-structured question file, a side-quest that saved time).

Recommendation: C - The fabricated walkthrough keeps the narrative clean and followable, while real snippets add credibility and show that these aren't theoretical tools. The real snippets can be short and focused — a 5-line excerpt from a breadcrumbs file, a question file showing how Q&A actually flows, etc.

A003: [RECOMMENDED] C

---

## Q004: Should the README include inline sample output (showing what generated files look like)?

Context: Beginners won't understand what `/scratchpad` or `/question` produces without seeing it. But inline samples add significant length. This decides how much "show don't tell" to include.

Options:
A) Full inline samples - Show a complete sample scratchpad (with JSON steps), question file, and commit message directly in the README using fenced code blocks. Adds ~80-100 lines but makes the README self-contained.
B) Abbreviated inline + link to examples - Show a short excerpt (10-15 lines) of each format inline, with a "see full example" link to an examples/ directory in the repo.
C) No inline samples - Describe the formats in prose and link to the SKILL.md files for format details. Keeps the README shorter but forces navigation.

Recommendation: B - Short excerpts give beginners enough to understand the format at a glance without bloating the README. Full samples are available for anyone who wants to dig deeper. An examples/ directory also serves as a living reference that can evolve independently of the README.

A004: [RECOMMENDED] B

---

## Q005: How should the skills reference section be structured?

Context: The current skills/README.md has three tables (foundation, non-invocable, composite). The root README needs a reference section but shouldn't just duplicate the skills README. This decides how to present the skill inventory to different audiences.

Options:
A) Unified table with categories - One table with a "Type" column (Foundation / Auto / Composite), one-liner descriptions, and links to each SKILL.md. Replace skills/README.md content with a redirect to the root README.
B) Two groups only - "What You Type" (invocable skills with `/command` syntax) and "What Works Automatically" (non-invocable). Simpler mental model for newcomers. Keep skills/README.md as the detailed architecture reference.
C) Visual dependency map - Replace tables with an ASCII or text-based diagram showing how composite skills call foundation skills, with brief descriptions alongside. More engaging but harder to maintain.
D) Minimal in root, full in skills/ - Root README has a simple bulleted list ("14 skills across 3 tiers — see the full inventory"). Keep the detailed tables in skills/README.md.

Recommendation: B - The "What You Type" vs. "What Works Automatically" framing is immediately intuitive. It answers the first question any user has: "what can I do?" Nobody's first question is "what's the architectural tier?" Keep skills/README.md as the deeper reference for architecture and step tracking.

A005: [RECOMMENDED] B

---

## Q006: Should the README include a "Design Philosophy" or "How I Think About This" section?

Context: The scratchpad plan suggests a philosophy section covering user-controls-commits, ephemeral-vs-permanent, plan-then-execute, etc. This is unusual for a README but could be the most distinctive and valuable part — it explains *why* the skills work the way they do.

Options:
A) Yes, prominent section - Give it a full `##` heading near the top (after quick start, before reference). 5-8 bullet points covering the core principles. This is what makes the project interesting beyond "here are some scripts."
B) Yes, but folded into the intro - Weave the principles into the opening paragraphs rather than giving them their own section. Less structured but more natural.
C) Yes, but at the bottom - Put it after the reference section as "Design Notes" for people who want to understand the thinking. Doesn't compete with the practical content.
D) No - Let the examples speak for themselves. Philosophy emerges from usage.

Recommendation: A - The design principles are the most differentiating content. They explain why someone would adopt these skills over ad-hoc prompting. Putting them near the top (but after the practical quick start) means motivated readers find them quickly while skimmers can jump to the reference.

A006: [RECOMMENDED] A

---

## Q007: Should we add a visual diagram showing the issue lifecycle flow?

Context: The full workflow (start-issue → tackle blocks → breadcrumbs → side-quests → finish-issue) is the key value story. A visual could make it instantly graspable, but ASCII art or Mermaid diagrams have tradeoffs in a README.

Options:
A) ASCII art flowchart - Works everywhere, renders in any terminal or viewer. Can be compact. Looks intentional in a developer tool README.
B) Mermaid diagram - GitHub renders Mermaid natively in markdown. Clean and professional. But doesn't render in terminal viewers, local markdown editors, or other Git hosts.
C) Both - ASCII for the README, link to a rendered Mermaid version in docs/.
D) Neither - The walkthrough scenario already tells the story sequentially. A diagram would be redundant.

Recommendation: A - ASCII art fits the developer-tool aesthetic, works everywhere, and is easy to maintain. It should be simple — a linear flow with one branch for side-quests — not trying to capture every edge case.

A007: [RECOMMENDED] A

---

## Q008: What section ordering gives the best reading experience?

Context: The README needs to serve both "scanning for 30 seconds" and "reading start to finish" use cases. Section order determines the first impression and the narrative flow.

Options:
A) Hook → Install → Quick Start → Full Workflow → Philosophy → Reference → Contributing
B) Hook → Philosophy → Install → Quick Start → Full Workflow → Reference → Contributing
C) Hook → Install → Full Workflow → Quick Start → Philosophy → Reference → Contributing
D) Hook → Install → Quick Start → Reference → Full Workflow → Philosophy → Contributing

Recommendation: A - This follows the standard open-source README pattern: explain what → how to get it → try it → see the full power → understand the thinking → detailed reference. Scanning readers get value from just the first three sections. Deep readers continue through to philosophy and reference.

A008: [RECOMMENDED] A

---

## Q009: Should the README link to official Claude Code skills documentation, and how prominently?

Context: The issue explicitly calls out "point to official AGENT skills config for references." This grounds the project in the official ecosystem and helps people who want to understand the underlying mechanism or create their own skills.

Options:
A) Dedicated "Resources" or "Learn More" section at the bottom - Include links to official Claude Code skills docs, SKILL.md format spec, and Claude Code documentation. Clean and conventional.
B) Inline contextual links - Mention the official docs where they're relevant (e.g., in the install section mention how skills work, in the philosophy section link to the skills architecture). No dedicated section.
C) Both - Inline links where relevant plus a collected "Resources" section at the end for people who want to go deeper.

Recommendation: C - Contextual links help readers in the moment ("oh, that's how skills work under the hood"), and a collected section at the end serves as a reference. Neither alone is sufficient.

A009: [RECOMMENDED] C

---

## Q010: Should we create an examples/ directory with sample output files?

Context: Q004 suggests abbreviated inline samples with links to full examples. This question asks whether to actually create that directory as part of this issue, or defer it.

Options:
A) Yes, create examples/ now - Include a sample scratchpad, question file, commit message, and breadcrumbs file. Makes Q004 option B fully workable. Adds ~4 files to the repo.
B) Defer - Keep the README self-contained for now. Create examples/ as a follow-up issue if the inline excerpts feel insufficient.
C) Use real files from .scratchpads/ etc. - Instead of fabricated examples, link to actual working files. Problem: these are git-ignored and won't be in the repo.

Recommendation: A - The examples/ directory directly supports the README's "show don't tell" approach and is small effort. Including sample files also helps people understand the file formats without reading SKILL.md specifications. Four short text files is minimal repo overhead.

A010: [RECOMMENDED] A

---

## Q011: Should the README address "how to fork/customize these skills for your own workflow"?

Context: Some readers will want to adapt skills rather than use them as-is. A brief section on customization could expand the audience, but it's also scope creep for this issue.

Options:
A) Brief section now - A short "Making These Your Own" paragraph: fork the repo, edit SKILL.md files, re-run install.sh. 5-6 lines. Low effort, high value for the fork-and-customize audience.
B) Defer to a separate doc - Mention it's possible ("these are just markdown files — fork and customize") but don't elaborate. Create a docs/customization.md later if there's interest.
C) Skip entirely - The SKILL.md files are self-documenting. Anyone technical enough to use Claude Code can figure out customization.

Recommendation: A - A brief mention is cheap and signals that this is meant to be adapted, not just consumed. It also reinforces the "no magic" philosophy — these are readable markdown files, not compiled binaries.

A011: [RECOMMENDED] A

---

## Q012: Should the opening hook include a "before/after" comparison showing Claude Code without skills vs. with skills?

Context: The strongest way to sell the value might be showing the contrast — what a typical Claude Code session looks like without structured skills (scattered files, no tracking, ad-hoc commits) vs. with them (organized workspace, step tracking, breadcrumb trail). This could be the most compelling element of the intro.

Options:
A) Yes, explicit before/after - Two short side-by-side scenarios or a "Without these skills... / With these skills..." comparison. Immediately communicates value.
B) Implied contrast - Describe what the skills provide and let readers infer the "before" from their own experience. Less dramatic but more concise.
C) Problem statement only - Open with the pain points ("Claude Code is powerful but sessions are unstructured, context is lost between tasks, commit messages are generic...") and then present the skills as the solution. Classic problem-solution framing.

Recommendation: C - A problem statement resonates immediately with anyone who's used Claude Code for real work. They'll recognize the pain points and understand the value proposition without needing an explicit side-by-side. It's also more concise than option A.

A012: [RECOMMENDED] C
