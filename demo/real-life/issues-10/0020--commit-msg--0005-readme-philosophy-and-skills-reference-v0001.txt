[docs] Add design philosophy and skills reference to README

The README showed what skills do (Quick Start) and how they compose (See It In Action) but never explained the thinking behind them. The "Why I Built These" section captures 7 principles distilled from real usage — files over chat, crash-proof context, user-controlled execution, and more. The skills reference replaces the bare pointer to skills/README.md with two inline tables: "What You Type" (9 invocable commands) and "What Works Automatically" (4 auto-consulted skills).

Benefits:
- Readers understand the philosophy before deciding whether to adopt
- Quick-scan tables answer "what can I do?" without leaving the README
- Architecture details still link out to skills/README.md for depth
