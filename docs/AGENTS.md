# Subagent Task Definitions for Docs

Each subagent type maintains one doc file. The orchestrator (`index.md`) links to all.

| Subagent | Owns | Scope |
|----------|------|-------|
| `task-distributor` | [AGENTS.md](AGENTS.md) | This file — subagent task assignments |
| `orchestrator` | [index.md](index.md) | Main index, cross-refs, session notes |
| `ui-designer` | [KIT.md](KIT.md) | Kit module API, component documentation, usage examples |
| `code-reviewer` | [SIGNAL_SAFETY.md](SIGNAL_SAFETY.md) | Signal type safety, FFI rules, patterns |
| `test-automator` | [SETTINGS_IMPLEMENTATION.md](SETTINGS_IMPLEMENTATION.md) | TDD coverage, network discovery tests |
| `build-engineer` | [GEMINI.md](GEMINI.md) | Zig build system, IO/stdlib migration |
| `deployment-engineer` | [WINDOWS_SETUP.md](WINDOWS_SETUP.md) | Cross-compilation, bundling, MSYS2 |
| `llm-architect` | [ZIG_DISCOVERIES.md](ZIG_DISCOVERIES.md) | Zig versioning, memory management, GTK FFI gotchas |

## Adding a new doc

1. Create the file in `docs/<NAME>.md`
2. Add subagent assignment to this table
3. Add entry to `index.md` table

## When to update

- **Kit API changes** → `KIT.md` (ui-designer)
- **New signal pattern** → `SIGNAL_SAFETY.md` (code-reviewer)
- **Test additions** → `SETTINGS_IMPLEMENTATION.md` (test-automator)
- **Build system changes** → `GEMINI.md` (build-engineer)
- **Platform support** → `WINDOWS_SETUP.md` (deployment-engineer)
- **Structural changes** → `index.md` (orchestrator)
