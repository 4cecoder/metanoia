# CLAUDE.md

Operational guidance for Claude Code (or any AI agent) working in this repository. Read this first — it captures hard-won lessons from real sessions, not aspirational process.

## Git safety — non-negotiable

- **Never push to any remote without being explicitly asked, including from a dispatched subagent.** This bit us once: a subagent told to "wire it in" interpreted that as license to `git push origin master`, taking several deliberately-unpushed local commits live along with its own. Every subagent prompt that has Bash/git access must explicitly state the constraint — no push, no force-push, no `--no-verify`, no rewriting history — don't rely on the subagent inferring it from context.
- Prefer many small, clean, well-described commits over one large one. Commit frequently; that's cheap and reversible. Pushing is not — treat it as a separate, explicit decision every time, never a side effect of "finish the task."
- This project tracks Zig **master nightly** (see `build.zig.zon`'s `minimum_zig_version`), not a stable release. APIs churn between sessions — re-verify assumptions (`grep` the actual installed std lib under `zig env`'s `std_dir`, or just try compiling) rather than trusting a prior session's notes or training data. See `docs/ZIG_DISCOVERIES.md` and `docs/GEMINI.md` for what's been learned so far, but confirm before relying on anything there if it's been a while since it was written.

## Known repo gotchas

- **`.gitignore`'s `models/` pattern must stay anchored (`/models/`), not bare (`models/`).** A bare `models/` matches *any* directory named "models" anywhere in the tree — it silently shadowed `src/models/` (real Zig source) and `mobile/.../models/` (real Kotlin source), not just the intended top-level ML-weights dir. This was fixed once, then recurred in a separate long-lived worktree that had branched before the fix landed — **check for this same class of drift whenever working across multiple parallel worktrees**, since `.gitignore`/CI config/lint config are not automatically kept in sync between them.
- `data/bible.db` and the wav clips actually referenced by `data/voices.json` are deliberately tracked in git (explicit `.gitignore` exceptions) — the app can't run without them, and they're well under GitHub's size limits (no git-lfs needed). Everything else under `data/` is genuinely unused dev scratch and should stay ignored — see `docs/MAINTENANCE.md` for the full reasoning and the exact file list.
- `vendor/` (native TTS/LLM build dependencies — a `qwentts.cpp` clone plus ~1.2GB of GGUF model weights) must **never** be committed — it's gitignored on purpose. Built locally per `aikit/README.md`'s instructions.

## Subagent practice

- **Bake verification into the task itself, not as a follow-up.** Ask subagents to run real commands and report real output (exit codes, actual file contents, actual numbers) rather than prose summaries — and independently spot-check anything consequential before repeating it as fact (re-run the build, re-check the diff, re-download and re-run if a claim looks surprising).
- For anything where correctness genuinely matters and isn't trivially checkable, use dual-blind adversarial QA (two independent reviewers, not shown each other's verdict) rather than trusting a single agent's self-report.
- This repo has a standalone Zig library, `aikit/` (native AI inference — TTS working via GGML/MLX backends, LLM inference in progress), with its own "no new external native deps" design principle documented in `aikit/README.md`. Read that before adding any new AI/ML capability — the temptation to just FFI-wrap an existing library is real and was explicitly rejected as the default going forward (the existing TTS backends are grandfathered exceptions, not the pattern to repeat).

## Where things live

- `docs/index.md` is the doc map. `docs/MAINTENANCE.md` has the original-language-caching-bug postmortem, testing strategy, and a quick-wins backlog. `docs/PACKAGING.md` covers macOS/Linux/Android release packaging. `docs/ZIG_DISCOVERIES.md`/`docs/GEMINI.md` are Zig-nightly API notes — check dates/versions before trusting them blindly.
- Windows support is deprioritized (not removed) — `windows_helper/`, `ci/*msys*`, `.github/workflows/release.yml` are left working but get no new effort. Current focus is macOS/Linux desktop (GTK4/Zig) and the Android (Kotlin) client.
- Experimental/risky native-rewrite work (the TTS/LLM native-Zig port) happens in an isolated git worktree until proven working, not directly on `master` — see `worktree-tts-native-port` branch history for the pattern.
