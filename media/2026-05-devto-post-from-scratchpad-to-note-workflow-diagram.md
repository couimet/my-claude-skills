Mermaid source for the note-vs-scratchpad workflow diagram. Rendered to `media/2026-05-devto-post-from-scratchpad-to-note-workflow-diagram.png`.

<!-- Extract the fenced mermaid block from this file into a temp file, then: mmdc -i <temp> -o media/2026-05-devto-post-from-scratchpad-to-note-workflow-diagram.png -b transparent -->

```mermaid
flowchart TD
    A[GitHub Issue] --> B["/start-issue"]
    B --> C{"Working document\ntype?"}
    C -->|default| D["/note"]
    C -->|"--scratchpad opt-in"| E["/scratchpad"]
    D --> F["Claude self-organizes execution in one session"]
    E --> G["/tackle-scratchpad-block\none or more steps per invocation"]
    G --> H["/finish-issue"]
    F --> H
    H --> I["PR description (doubles as commit message)"]

    classDef secondary stroke-dasharray:5 5
    class E,G secondary
```
