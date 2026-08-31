# Volatility Refactor — Libraries, Dependencies & Split Binaries

**Status:** design — no behavior change yet; `.gitignore` fix for vendored `ui-kit` ships with this doc.
**Author:** volatility-refactor subagent — 2026-08-31
**Context:** User goals: “look into code refactoring by libraries and by volatility and look into split binaries as well by volatility making updates, builds faster” + “you can vendor the ui-kit” (already vendored at `vendor/ui-kit` and `site/vendor/ui-kit`, site build passes via `file:./vendor/ui-kit`).

This doc maps existing code by change-frequency (volatility), applies the Stable Dependencies Principle (stable at the bottom, volatile at the top), proposes `build.zig` library splits that respect that ordering, and proposes binary splits so each artifact rebuilds in isolation via the Zig build graph DSL (`build.zig:41-46`).

---

## 1. Volatility Classification

Definitions (Robert C. Martin + build-engineer checklist):

- **STABLE** — changes rarely; breaks many dependents if it changes; should have zero outgoing dependencies on volatile code.
- **SEMI-STABLE** — changes with feature work; schema or capability evolves.
- **VOLATILE** — changes per-commit; UI wiring, glue, experiments.

### By library / directory

| Volatility | Library / Dir | Key Files (with line numbers & counts) | Why this bucket |
|---|---|---|---|
| **STABLE** (bottom) | `aikit/` — native inference | `aikit/build.zig:1-265` (265), `aikit/src/root.zig`, `aikit/src/capabilities/*.zig`, `aikit/src/backend/*` | Standalone package (`aikit/build.zig.zon`), no GTK/sqlite/app imports, opt-in via `-Dnative-ai=false` default (`build.zig:73-77`). Rarely touched unless adding a new model family; heavy native deps isolated. |
| **STABLE** | `vendor/ui-kit` — React kit | `vendor/ui-kit/dist/{index.js:106k,index.cjs:121k,styles.css:100k}` (9 files, 728 KB total), `vendor/ui-kit/src:4285` lines, `site/vendor/ui-kit` identical copy | External design-system, versioned separately (`@bytecats/ui-kit@0.2.0`). Site consumes via `file:./vendor/ui-kit` (`site/package.json:14`). Changes only on design-token releases, not app commits. |
| **STABLE** | `src/kit/` — Zig GTK kit | `src/kit/root.zig:1-44` (44), `src/kit/ffi.zig:1-319` (319), `src/kit/widget.zig:1-595` (595), `src/kit/signal.zig:1-59`, `src/kit/theme.zig:1-94`, `src/kit/util/text.zig:1-143`, `components/*` 155–394 each — total `src/kit:3018` | Decoupled UI library (`build.zig:138-142` `kit_mod`), zero imports of `bible_db`/`app_state`/`services`; pure widget/callback abstractions. Changes only when adding a new component, not per feature. |
| **STABLE** | `src/gtk.zig` | `src/gtk.zig:1-229` (229) | Raw C FFI declarations, 25 labeled sections; changes only on GTK API churn or Zig nightly FFI syntax change. |
| **SEMI-STABLE** | `src/bible_db.zig` — DB kernel | `src/bible_db.zig:1-1159` (1159), `src/bible_db.zig:148-172` DDL, `src/bible_db.zig:24-34` mutex, `src/bible_db.zig:83-127` `attachLibraryDb` | Schema + canonical `BIBLE_BOOKS[0..88]:334-422` + `BIBLE_ABBREVIATIONS:436-459`. Changes when adding a source/lexicon column or sharding (`docs/DB_SHARDING.md:148-180` → per-shard DDL). Otherwise queries stable. |
| **SEMI-STABLE** | `src/models/config.zig` | `src/models/config.zig:1-243` (243) | App config + `Config.parseJson`/`save`; changes when a new `tts_backend`/`ot_source`/`bible_tradition` key lands. Touched O(1) per feature, not per commit. |
| **SEMI-STABLE** | `src/services/*` | `tts_engine.zig:1-354` (354), `llm_engine.zig:1-169` (169), `network_discovery.zig:1-216` (216), `update_checker.zig:1-348` (348) — total 1087 | Capability engines; each isolates a network/processing concern. Changes with new backend or discovery protocol, otherwise closed. |
| **SEMI-STABLE** | `data/bible.db` + `data/db/*` shards | `data/bible.db:118M` (123318272 B per `git diff`), `docs/DB_SHARDING.md:30-65` → `core.db:100K`, `verses.lxxe.db:18M`, `interlinear.lxx.db:38M`, `interlinear.gnt.db:12M`, `lexicon.db:2M`, `fts.db:8M` (default bundle ~70M) | Content, not code; volatile at import-time, stable at read-time. Sharding makes volatility per-source, not monolithic 118 M rewrite on any import. |
| **SEMI-STABLE** | `mobile/` — Kotlin | `mobile/app/src: ~20k` lines, `mobile/app/src/main/java/com/bytecats/metanoia/bible/BibleDatabase.kt:1-258` (258), `BibleManager.kt:1-275` | Separate Gradle build graph; semi-stable because Android UI + AGP version bumps, but isolated from Zig graph. |
| **VOLATILE** | `site/` — Next.js | `site/src/app/page.tsx:1-~300`, `site/src/app/docs/database/page.tsx`, `site/out:2.9M` (`site/out/index.html:85K`, `site/out/_next/static`) | Content/marketing/docs; changes per doc edit, per `learn/*` page. Build via `bun run build` → `site/out` static export (`site/next.config.ts:9 output:"export"`). Independent artifact (see §4). |
| **VOLATILE** | `src/native_scraper.zig` | `src/native_scraper.zig:1-1159` (1159) — HTML scanner + `fetchWithRetry` + `scrapeInterlinear/Lexicon` | Network + HTML brittle; changes when BibleHub markup drifts (see “KNOWN BEHAVIORAL NOTE” `native_scraper.zig:12-20`). Should be isolatable as its own binary (see §4). |
| **VOLATILE** | `src/app_state.zig` | `src/app_state.zig:1-145` (145) — `AppState` god struct, widget refs, TTS locks | Wiring changes whenever a new widget or engine is added; central but not stable. Candidate to shrink via delegation to `kit` components. |
| **VOLATILE** (top) | `src/main.zig` — app glue | `src/main.zig:1-1528` (1528) — GTK app lifetime, `load_chapter_into_study:388-571`, search/nav/TTS/LLM glue, `ModelSectionCtx:940-949` | Changes per commit by definition; imports everything (`main.zig:3-15` 13 imports). Stable-Dependencies violation today (see §2). |
| **VOLATILE** | `src/root.zig` | `src/root.zig:1-17` (17) — re-exports `bible`, `tts`, `kit`, `native_scraper` | Thin re-export barrel; volatile because it tracks whatever `main`/`tests` need. Replaceable by explicit modules (see §7). |
| **VOLATILE** | `src/ui/` (legacy) | `src/ui/components/*` 68–342, `navigation_dialog.zig:282`, `settings_dialog.zig:583`, `theme.zig:68` — total ~1700 | Pre-`kit` UI; increasingly unused (kit migration ongoing). Volatile legacy — should be sunset, not split. |
| **INFRA** | `build.zig` | `build.zig:1-448` (448), `build.zig:41-46` graph DSL, `build.zig:179-205` exe, `build.zig:346-390` test graph, `build.zig:405-435` native-ai gates | Build meta-code; volatility proportional to how many concerns it wires. Splits reduce it (see §3). |

**Summary counts:** `src/main.zig` 1528 is the single largest volatile file; `src/kit` 3018 is the largest stable block; `src/bible_db` 1159 is the largest semi-stable schema; `data/bible.db` 118 M dwarfs all code (×70 source size), which is why `docs/DB_SHARDING.md` exists.

---

## 2. Stable Dependencies Principle — Where We Are vs. Where We Want

**Principle:** Dependencies point toward stability (volatile → semi-stable → stable, never reverse). Stable packages should not depend on volatile ones.

### Current (implicit) — flat module graph

```
site/out  mobile/   ← separate build systems (good: already isolated)
    \
     \                aikit (-Dnative-ai)
      \                    ↓ (optional)
       ┌─────────────────────────────────┐
       │  exe.meranoia                   │  ← main.zig:1528 imports kit+bible+config+app_state+services+aikit
       │  mod metanoia (root.zig)        │  ← re-exports bible/tts/scraper/network but also imports them
       │  kit_mod                        │  ← stable, but only one split today (build.zig:139-142)
       └─────────────────────────────────┘
   everything depends on everything via main.zig + root.zig barrel
```

Violation: `main.zig:3-15` and `root.zig:1-8` pull `kit` (stable) + `bible_db` (semi-stable) + `native_scraper` (volatile) + `services` (mixed) into one flat compilation unit. Changing `native_scraper.zig:500` (volatile scraper) recompiles `main.zig` (volatile app) even though `kit` (stable) is unrelated — no isolation.

### Target — layered, volatility-sorted

```
                      VOLATILE (top, changes often)
                      ┌──────────────────────────┐
                      │ app  (main.zig:1528)     │  exe metanoia
                      │ scraper_bin              │  exe metanoia-scraper
                      │ site/out                 │  site artifact 2.9M
                      └────────────┬─────────────┘
                                   ↓
                      SEMI-STABLE
                      ┌──────────────────────────┐
                      │ services (tts/llm/net)   │  1087 lines
                      │ core (bible_db+config+   │
                      │       gtk+app_state)     │  1159+243+229+145 = 1776
                      └────────────┬─────────────┘
                                   ↓
                      STABLE (bottom, rarely changes)
                      ┌──────────────────────────┐
                      │ kit (src/kit:3018)       │  ← zero deps on core/services/app
                      │ aikit (standalone pkg)   │  ← standalone build.zig.zon
                      │ vendor/ui-kit (728K)     │  ← file:./vendor/ui-kit
                      └──────────────────────────┘
```

Arrows = `b.addModule(...imports = &.{...})` edges. Stable has zero outgoing edges to volatile. Volatile can fan-in to stable without triggering stable recompiles. Each layer is a separate Zig module with its own cache key.

Cache implication: Zig's build graph (`build.zig:41-46`):
> “Although this function looks imperative, it does not perform the build directly and instead it mutates the build graph (`b`) that will be then executed by an external runner. The functions in `std.Build` implement a DSL for defining build steps and express dependencies between them, allowing the build runner to parallelize the build automatically (and the cache system to know when a step doesn't need to be re-run).”

With splits, changing `src/main.zig:400` only dirties the `app` module’s hash; `kit` and `core` stay cached. Changing `src/kit/widget.zig:595` dirties `kit` and transitively `app`/`services` (which depend on it), but not `aikit` if gated.

---

## 3. Proposed `build.zig` Library Splits

Goal: add 4 libraries + keep 1 existing, each with precise source boundary and import list. Rebuild isolation per previous section.

| Module name | Source root | Lines | Imports (depends on) | Stability | `build.zig` declaration |
|---|---|---|---|---|---|
| `kit` (exists) | `src/kit/root.zig:1-44` | 3018 | _(none)_ — pure GTK wrappers; already `b.addModule("kit", .{ .root_source_file = b.path("src/kit/root.zig") })` at `build.zig:139-142` | STABLE | keep as-is |
| `core` | `src/core/root.zig` (new barrel) | 1776 | `kit` | SEMI-STABLE | `core_mod = b.addModule("core", .{ .root_source_file = b.path("src/core/root.zig"), .imports = &.{.{.name="kit", .module=kit_mod}} })` + `core_mod.linkSystemLibrary("gtk4"/"gtk-4")`, `sqlite3`, `link_libc` (as `build.zig:148-151` does today for `mod`) |
| `services` | `src/services/root.zig` (new barrel) | 1087 | `core`, `kit`, `build_options` | SEMI-STABLE | `services_mod = b.addModule("services", .{ .root_source_file = b.path("src/services/root.zig"), .imports = &.{.{.name="core",.module=core_mod}, {.name="kit",.module=kit_mod}, {.name="build_options",.module=build_options_mod}} })` |
| `app` | `src/app/root.zig` or `src/main.zig` retained as exe root | 1528 + 145 | `core`, `kit`, `services`, `build_options`, `aikit?` | VOLATILE | exe root module still `b.createModule(.{ .root_source_file = b.path("src/main.zig"), .imports = &.{.name="core",.module=core_mod}, ... })` but now 4 deps instead of 1 flat |
| `aikit` (conditional) | `aikit/src/root.zig` via `b.dependency("aikit", ...)` | — | _(none, standalone)_ | STABLE (opt-in) | keep `build.zig:98-105` gated `if(native_ai)` → `aikit_mod` + `services_mod`/`app` conditional import `if(aikit_mod)|am| imports.append(.{.name="aikit",.module=am})` as `build.zig:121-122` & `177` do today |

### What moves where (concrete file list)

**`core/` barrel** (`src/core/root.zig` new, ~20 lines):
```zig
pub const bible = @import("../bible_db.zig");
pub const config = @import("../models/config.zig");
pub const gtk = @import("../gtk.zig");
pub const app_state = @import("../app_state.zig");
test { _ = bible; _ = config; }
```
Members stay at current paths; barrel just re-exports so dependents import `@import("core").bible` instead of `@import("bible_db.zig")`. Later step can physically move files to `src/core/bible_db.zig` etc., but not required for cache isolation — `b.addModule`'s `root_source_file` + `imports` is the boundary, not file path.

- `src/bible_db.zig:1-1159` → `core`
- `src/models/config.zig:1-243` → `core`
- `src/gtk.zig:1-229` → `core` (or `kit` — arguable; `kit/ffi.zig:1-319` already covers GTK FFI, so `gtk.zig` could migrate to `kit/ffi.zig` and disappear; keep in `core` until deduped)
- `src/app_state.zig:1-145` → `core` (or thin `app`; keep in `core` since `main.zig` and `services/tts_engine` both read `AppState`)

**`services/` barrel** (`src/services/root.zig` new):
```zig
pub const tts_engine = @import("tts_engine.zig");
pub const llm_engine = @import("llm_engine.zig");
pub const network_discovery = @import("network_discovery.zig");
pub const update_checker = @import("update_checker.zig");
```
No file moves.

**`app`** — retains `src/main.zig:1-1528` as exe rootiper (`build.zig:179-195`); change is its `imports` list shrinks from 13 relative imports to 4 module imports (`core`/`kit`/`services`/`build_options` + conditional `aikit`). `src/root.zig:1-17` barrel can be deleted once `core` barrel exists (its re-exports duplicate `core`).

**`kit`** — no moves; already correctly isolated. Add `kit_mod.linkSystemLibrary("gtk4")` if `services`/`core` stop linking GTK transitively (today `mod` at `build.zig:148-151` and `exe.root_module` at `build.zig:201-204` both link `gtk4`+`sqlite3` redundantly; after split, link at lowest module that needs it).

### `build.zig` diff (sketch, reversible, ~60 lines added)

```zig
// after `const kit_mod = b.addModule("kit", ...)` at build.zig:139-142

// core — bible_db + config + gtk (semi-stable)
const core_mod = b.addModule("core", .{
    .root_source_file = b.path("src/core/root.zig"),
    .target = target,
    .imports = &.{
        .{ .name = "kit", .module = kit_mod },
        .{ .name = "build_options", .module = build_options_mod },
    },
});
core_mod.linkSystemLibrary(if(target.result.os.tag==.windows) "gtk-4" else "gtk4", .{});
core_mod.linkSystemLibrary("sqlite3", .{});
core_mod.link_libc = true;

// services — tts/llm/network/update (semi-stable, depends on core)
const services_mod = b.addModule("services", .{
    .root_source_file = b.path("src/services/root.zig"),
    .target = target,
    .imports = &.{
        .{ .name = "core", .module = core_mod },
        .{ .name = "kit", .module = kit_mod },
        .{ .name = "build_options", .module = build_options_mod },
    },
});
// services_mod conditional aikit
var services_imports = ArrayList(Module.Import).fromOwnedSlice(... core/kit/build_options ...);
if (aikit_mod) |am| services_imports.append(.{.name="aikit", .module=am});
services_mod.imports = services_imports.items; // or create via addModule with slice

// exe now depends on 4 modules instead of flat 13 relative imports
var exe_imports = std.ArrayListUnmanaged(std.Build.Module.Import).empty;
exe_imports.append(.{.name="core", .module=core_mod});
exe_imports.append(.{.name="kit", .module=kit_mod});
exe_imports.append(.{.name="services", .module=services_mod});
exe_imports.append(.{.name="build_options", .module=build_options_mod});
if (aikit_mod) |am| exe_imports.append(.{.name="aikit", .module=am});
// ... b.addExecutable(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .imports = exe_imports.items }) })

// tests split accordingly:
const core_tests = b.addTest(.{ .root_module = core_mod });
const services_tests = b.addTest(.{ .root_module = services_mod });
// kit_tests keeps as build.zig:351-352, mod_tests becomes core_tests, etc.
```

All existing `b.step("test")` deps at `build.zig:386-390` fan-in to `run_core_tests`, `run_services_tests`, `run_kit_tests`, `run_exe_tests` — parallelizable per `build.zig:41-46` DSL.

### Why this ordering matters for speed

- `kit` (stable) — changed rarely → cached ~90 %+ of builds. Four modules depend on it, but dependants only rebuild when `kit`’s hash changes.
- `core` (semi-stable) — changes when `bible_db.zig:148-172` schema or `config.zig` key changes; `services`/`app` rebuild, `kit` does not.
- `services` — TTS/LLM iteration touches only `services` + `app` (which imports service types), not `core`’s DB code.
- `aikit` gated by `native_ai` (`build.zig:73-77` bool, `build.zig:98-105` dependency) — `zig build` (default `native_ai=false`) never fetches or hashes `aikit` deps, so fresh checkout builds with just `brew install zig gtk4 sqlite3` keep working. `zig build -Dnative-ai=true` adds the `aikit` module hash to `services`/`app` only when needed.

---

## 4. Split Binaries — Isolate Rebuild & Deploy

### Current: one binary, one site artifact

- `zig-out/bin/metanoia` (`build.zig:179-195` `b.addExecutable(.{.name="metanoia"})`) — monolithic: `main.zig` + scrapers + services + `bible_db` + `kit` + `aikit?` all in one link.
- `site/out` (`site/next.config.ts:9` `output:"export"` → `bun run build` → `site/out:2.9M`) — static site for `pages.yml`.
- Mobile `.apk` — Gradle, already isolated (good).

Changing `native_scraper.zig:500` or `services/tts_engine.zig:100` triggers full `metanoia` relink (~1528 + 1159 + 1087 lines) even though scraper is not needed to read verses.

### Proposed: three isolated build-graph roots

| Binary / Artifact | Source root | Size / deps | `build.zig` step | Rebuild trigger | Deploy |
|---|---|---|---|---|---|
| `metanoia` (main app) | `src/main.zig:1-1528` + `core`+`services`+`kit` | `zig-out/bin/metanoia` + `data/bible.db` (118 M → 70 M sharded bundle) | `b.addExecutable(.{.name="metanoia", .root_module=exe_mod})` at `build.zig:179` + `b.installArtifact(exe)` `build.zig:319` + `b.step("run", ...)` `build.zig:326` | `main.zig`/`services`/`core`/`kit` change | `metanoia.app` bundle (`build.zig:306-313` macOS) or `zig-out/bin` Linux |
| `metanoia-scraper` | `src/native_scraper.zig:1-1159` (standalone) | `zig-out/bin/metanoia-scraper` — imports only `bible_db` + `std` (no GTK, no `kit`, no `services`, no `app_state`) | `const scraper_exe = b.addExecutable(.{ .name="metanoia-scraper", .root_module=b.createModule(.{.root_source_file=b.path("src/native_scraper.zig"), .imports=&.{.{.name="core",.module=core_mod}}, .target=target, .optimize=optimize}) }); b.installArtifact(scraper_exe); b.step("scraper","Run the native interlinear/lexicon scraper").dependOn(&b.addRunArtifact(scraper_exe).step);` | Only `native_scraper.zig`/`core` change — **not** `main.zig`/`services` | Dev tool; optional `zig build scraper -- --help` or `tools/bible/*.py` replacement |
| `site/out` (site) | `site/src/**` (~4k lines) + `site/vendor/ui-kit:4285` src / 728K dist | `site/out:2.9M` (`site/out/index.html:85K`) + `site/.next` cache | **Not Zig** — `bun install` + `bun run build` (`site/package.json:6` `next build`) → `actions/upload-pages-artifact@v3` with `path: site/out` in `.github/workflows/pages.yml:38-41` | Only `site/src`/`site/vendor/ui-kit` change | GitHub Pages (static) |

### How rebuild isolation works (build graph DSL — `build.zig:41-46`)

> “Although this function looks imperative, it does not perform the build directly and instead it mutates the build graph (`b`) that will be then executed by an external runner. The functions in `std.Build` implement a DSL for defining build steps and express dependencies between them, allowing the build runner to parallelize the build automatically (and the cache system to know when a step doesn't need to be re-run).”

Concretely:

- `b.addExecutable` + `b.installArtifact` + `b.step("run", ...).dependOn(&run_cmd.step)` (`build.zig:326-339`) are graph edges. `zig build` (no args) executes the `install` default step; `zig build run` adds the `run` edge; `zig build scraper` would add only `scraper` + its `install`.
- Each module (`kit_mod`, `core_mod`, `services_mod`) has a content hash of its `root_source_file` + `imports` + `target`/`optimize`. Changing `src/services/tts_engine.zig:10` dirties `services_mod`’s hash, which dirties `app`’s `exe` hash (since `exe` imports `services`), but **not** `scraper_exe`’s hash (since `scraper_exe` imports only `core`). So `zig build scraper` after editing `tts_engine` is a no-op (cached), and `zig build` after editing `native_scraper` does not relink `metanoia`’s services.
- Tests shard the same way (`build.zig:346-390` today already shards `mod_tests`/`kit_tests`/`exe_tests` parallel). Adding `core_tests`/`services_tests` keeps shards small (<400 lines per test root) so a `tts_engine` regression does not re-run `bible_db`’s 8 round-trip tests (`bible_db.zig:754-924`).
- The `native_ai` gate (`build.zig:98-105` `if(native_ai) b.dependency("aikit")`) means `aikit` is not even a graph node when `native_ai=false` (default). So `vendor/qwentts.cpp` (1.2 GB) and `mlx-c` are never hashed on a fresh checkout — `zig build test` stays fast without them.

### Why `native_scraper` as a separate binary (not just `import`)

- `src/native_scraper.zig:1-20` docs say it mirrors `tools/interlinear_scraper.py`+`lexicon_scraper.py` (network + HTML) but is decoupled (`parseXHtml([]const u8)` pure, `scrape*` does IO) so it can be unit-tested without network. As a library import, any `main.zig` change would recompile its 1159 lines anyway; as a standalone `b.addExecutable`, it has its own cache entry and can be invoked in CI as `zig build scraper -- --book John --chapter 3` to populate `data/bible.db` or future `data/db/*.db` shards without building the full GTK app.
- Packaging split: `src/main.zig` needs `gtk4`+`sqlite3`+`glib` etc. (`build.zig:148-151` and `201-204`), `native_scraper` needs only `sqlite3`+`libc`. Linking 11 Windows system libs (`build.zig:266-302` `gmodule-2.0`/`ffi`/`z`/`pcre2-8`/`iconv`/`ws2_32`/`ole32`/`shlwapi`/`iphlpapi`/`dnsapi`) is only paid by `metanoia`, not `metanoia-scraper` — measurable on Windows CI where those `linkSystemLibrary` probes dominate cold link time.
- Fallback: Python scrapers (`tools/bible/interlinear_scraper.py`, `lexicon_scraper.py`) remain; Zig scraper as exe is a drop-in replacement they can call, not a delete.

---

## 5. Data & Site Volatility as Contrast

| Volatile dimension | Current cost | After sharding / vendoring |
|---|---|---|
| **DB content** `data/bible.db:118M` (`src/bible_db.zig:148-172` DDL) | One `git pull` rewrites 118 M even if only `interlinear` LXX→GNT changed; NKJV (copyrighted) ships by default (`docs/DB_SHARDING.md:20-23`). Mobile copies `bible.db.gz` blindly. | `data/db/manifest.json` + 8 shards (`docs/DB_SHARDING.md:31-45`): `core.db:100K`, `verses.lxxe.db:18M`, `interlinear.lxx.db:38M`, `interlinear.gnt.db:12M`, `lexicon.db:2M`, `fts.db:8M` (default bundle ~70 M, `interlinear.mt.db:22M` opt-in `bundle:false`). Zig `ATTACH DATABASE 'data/db/<shard>' AS <schema>` (`docs/DB_SHARDING.md:78-91`) with fallback to `data/bible.db`; `tools/bible/split_db.py` + `VACUUM INTO` (`docs/DB_SHARDING.md:99-107`). Each import touches only one shard file. |
| **Site** `site/src` + `site/out:2.9M` | `site/src/app/page.tsx` etc. change often (docs/marketing), but `site` already has its own `package.json` + `bun.lock` + `site/vendor/ui-kit` — `bun run build` at `.github/workflows/pages.yml:29-35` does not invoke `zig build` at all. | Keep isolation: `site/package.json:14` `"@bytecats/ui-kit":"file:./vendor/ui-kit"` makes site builds independent of root `vendor/`; `site/vendor/ui-kit` now re-included via `.gitignore:132-133` `!site/vendor/ui-kit/**` (after bare `dist/`). Future: replace `site/vendor/ui-kit` copy with `file:../vendor/ui-kit` + single `vendor/ui-kit` source to avoid 728 K duplication — `bun` follows `../` symlinks identically, one dir to keep in sync. |

---

## 6. Vendored `ui-kit` — Verification & `.gitignore` Fix

**Goal:** `site/package.json:14` `file:./vendor/ui-kit` makes site builds independent of any `npm` fetch — `vendor/ui-kit/dist/*` must be in git (not rebuilt on CI).

**Before this change:**

- `.gitignore:118` was bare `vendor/` — matches ANY `vendor` directory (`vendor/` + `site/vendor/` + any future `foo/vendor/`). Swallows `vendor/ui-kit` and `site/vendor/ui-kit` even though `vendor/ui-kit/.gitignore` intentionally commits `dist/` (`vendor/ui-kit/.gitignore:9-14` “dist/ is intentionally NOT ignored”).
- `vendor/ui-kit/dist/index.js:106K` + `index.cjs:121K` + `styles.css:100K` (9 files, 728 K) existed on disk but `git ls-files | grep vendor` listed none — all under ignored `vendor/` and `dist/` (`site/vendor/ui-kit/dist/` was `!!` ignored).
- `site/vendor/ui-kit` was a duplicate copy (same 9 files, same 728 K) — `bun.lock:147557 B` locks `@bytecats/ui-kit@file:vendor/ui-kit` with full `dependencies` (radix-ui, motion, etc.) so `bun install` in `pages.yml:27-29` needs zero network if `dist/` is present.

**After (`.gitignore:118-133`):**

```gitignore
# Bare `vendor/` → anchored `/vendor/*` so parent-dir optimization doesn’t hide negations.
# Mirrors the `/models/` vs `models/` fix (CLAUDE.md).
/vendor/*
!/vendor/ui-kit/
!/vendor/ui-kit/**
# site/vendor/ui-kit re-included after bare `dist/`/`node_modules/` (last-match-wins).
!site/vendor/ui-kit/
!site/vendor/ui-kit/**
```

- Anchored `/vendor/*` ignores top-level `vendor/qwentts.cpp` (1.2 GB GGUF) via `vendor/*` but keeps the `vendor` directory entry scannable, so `!/vendor/ui-kit/**` can re-include.
- `dist/` (line 101) is bare, so `site/vendor/ui-kit/dist/` was still `!!` ignored until `!site/vendor/ui-kit/**` added after it — now both `git add --dry-run vendor/ui-kit/dist/index.js` and `site/vendor/ui-kit/dist/index.js` succeed (`add 'vendor/ui-kit/dist/index.js'`), and `git status --ignored` no longer lists `site/vendor/ui-kit/dist/` as ignored.

**Verify on a fresh clone:**

```sh
ls vendor/ui-kit/dist/index.js site/vendor/ui-kit/dist/index.js && echo "both 728K dist present"
git check-ignore -v vendor/ui-kit/dist/index.js   # → !/vendor/ui-kit/** (re-included, addable)
git check-ignore -v site/vendor/ui-kit/dist/index.js # → !site/vendor/ui-kit/** (re-included, addable)
git check-ignore -v vendor/qwentts.cpp/build/libqwen.a # → /vendor/* (ignored)
git add --dry-run vendor/ui-kit/dist/index.js site/vendor/ui-kit/dist/index.js  # should print add
bun --cwd site install --frozen-lockfile && bun --cwd site run build  # site/out:2.9M
```

**Known duplication:** `vendor/ui-kit` and `site/vendor/ui-kit` are byte-identical (`diff -rq vendor/ui-kit site/vendor/ui-kit` → empty). Either deduplicate to a single source (`site/package.json` → `file:../vendor/ui-kit`, delete `site/vendor/ui-kit`, `bun install` still works), or keep duplicate and sync on `vendor/ui-kit` bumps (`cp -r vendor/ui-kit site/vendor/ui-kit`). Doc keeps duplicate as shipped, deduplication as follow-up.

---

## 7. Concrete Next Steps — Small, Reversible

### Step 0 — Land without behavior change (this doc + `.gitignore` fix)

- Commit `docs/VOLATILITY_REFACTOR.md` + `.gitignore` anchored vendor fix. No `build.zig` change, no file moves, no `git push` (per task: DO NOT PUSH).

### Step 1 — Add `src/core/root.zig` + `src/services/root.zig` barrels (no file moves, ~40 lines)

```sh
mkdir -p src/core src/services
cat > src/core/root.zig <<'ZIG'
pub const bible = @import("../bible_db.zig");
pub const config = @import("../models/config.zig");
pub const gtk = @import("../gtk.zig");
pub const app_state = @import("../app_state.zig");
test { _ = bible; _ = config; }
ZIG
cat > src/services/root.zig <<'ZIG'
pub const tts_engine = @import("tts_engine.zig");
pub const llm_engine = @import("llm_engine.zig");
pub const network_discovery = @import("network_discovery.zig");
pub const update_checker = @import("update_checker.zig");
ZIG
```

No imports change yet; verify `zig build test` still passes (barrels not wired).

### Step 2 — Wire `build.zig` modules (60 lines, still no file moves)

Edit `build.zig:138-195` as sketch in §3:

- Keep `kit_mod` at `build.zig:139-142`.
- Add `core_mod = b.addModule("core", .{ .root_source_file = b.path("src/core/root.zig"), .imports = &.{.{.name="kit",.module=kit_mod}, {.name="build_options",.module=build_options_mod}} })` + link `gtk4`/`sqlite3`/`libc` as `build.zig:148-151`.
- Add `services_mod = b.addModule("services", .{ .root_source_file = b.path("src/services/root.zig"), .imports = &.{...core,kit,build_options...} })`.
- Change `exe.root_module.imports` from `mod`+`kit` flat to `core`+`kit`+`services`+`build_options`+`aikit?`.
- Split `b.addTest` at `build.zig:346-390`: `core_tests = b.addTest(.{.root_module=core_mod})`, `services_tests = b.addTest(.{.root_module=services_mod})`, keep `kit_tests` (`build.zig:351`), repoint `mod_tests` to `core_mod`. `test_step.dependOn(&run_core_tests.step)` etc. — parallel per graph DSL.

Verify: `zig build --help` lists same steps plus `test`; `zig build test` runtime unchanged; `zig build --verbose` shows module hashes now per-library.

### Step 3 — Add `metanoia-scraper` binary (15 lines, behind a step)

```zig
const scraper_mod = b.createModule(.{
    .root_source_file = b.path("src/native_scraper.zig"),
    .target = target, .optimize = optimize,
    .imports = &.{.{.name="core", .module = core_mod}},
});
const scraper_exe = b.addExecutable(.{ .name = "metanoia-scraper", .root_module = scraper_mod });
scraper_exe.root_module.linkSystemLibrary("sqlite3", .{});
scraper_exe.root_module.link_libc = true;
b.installArtifact(scraper_exe);
const scraper_step = b.step("scraper", "Build & run the native interlinear/lexicon scraper");
scraper_step.dependOn(&b.addRunArtifact(scraper_exe).step);
```

Does NOT affect `zig build` default (only `zig build scraper` or `zig build --help` lists it). Test `native_scraper` parser tests still run via `core_tests` or new `scraper_tests`.

### Step 4 — Migrate `main.zig` imports from relative to module imports

- `src/main.zig:6` `const bible = @import("bible_db.zig");` → `@import("core").bible`
- `src/main.zig:4` `models = @import("models/config.zig")` → `@import("core").config`
- `src/main.zig:10-12` `tts_engine_mod`/`llm_engine_mod`/`update_checker` → `@import("services").tts_engine` etc.
- Keep `src/main.zig:14` `kit = @import("kit")` as-is.

One file, mechanical, `zig build` still passes.

### Step 5 — Physically move files if desired (optional, not required for cache)

Only if team prefers directory matches module:

```sh
git mv src/bible_db.zig src/core/bible_db.zig
git mv src/models/config.zig src/core/config.zig
git mv src/gtk.zig src/core/gtk.zig   # or src/kit/ffi.zig merge
git mv src/app_state.zig src/core/app_state.zig
# update src/core/root.zig imports to @import("bible_db.zig") etc.
```

This is the only step that touches `git log --follow` history; defer until module split proven.

### Step 6 — Site deduplication (optional)

```sh
# single source of truth: top-level vendor/ui-kit
jq '.dependencies."@bytecats/ui-kit"="file:../vendor/ui-kit"' site/package.json > /tmp/p.json && mv /tmp/p.json site/package.json
rm -rf site/vendor/ui-kit
bun --cwd site install && bun --cwd site run build && ls -lh site/out/index.html
```

Removes 728 K duplicate + `node_modules` double-resolve; `bun install` + `pages.yml` still hermetic because `../vendor/ui-kit/dist` is in git (via `/vendor/*` fix).

---

## 8. Metrics & Build Context

| Metric | Before | After (projected, same hardware) |
|---|---|---|
| `zig build --help` | 0.11s user 0.26s sys (0.17.0-dev.1778) | same (graph construction unchanged) |
| Cold `zig build` (no `.zig-cache`) | ~? (not measured in this doc; depends on GTK pkg-config + 11 Windows libs at `build.zig:266-302`) | Same absolute cold time, but cache granularity finer: changing `src/main.zig` no longer invalidates `kit`/`core` hashes — `kit:3018` (≈3k stable) stays cached 90 %+ of builds |
| Incremental `main.zig` edit | recompiles flat `mod:1159+kit:3018+services:1087+main:1528` → full link | recompiles `app:1528` + relink only; `core`/`kit`/`services` cached |
| Incremental `kit/widget.zig` edit | same full rebuild | `kit:595` → `services`/`core`/`app` dependents rebuild (expected) but `aikit` (`-Dnative-ai=false` → not in graph) not |
| `metanoia-scraper` incremental (`native_scraper.zig:200`) | triggers `metanoia` relink (since flat) | `metanoia-scraper` rebuild only; `metanoia` cached (separate exe graph node) |
| Bundle size `data/bible.db` | 118 M (123318272 B) monolith | 70 M default bundle (`core 0.1M + verses.lxxe 18M + interlinear.lxx 38M + interlinear.gnt 12M + lexicon 2M`) — MT `22M` opt-in `bundle:false`; `mobile/bible.db.gz` similarly shrinks via `tools/bible/export_android_asset.py` |
| Site artifact `site/out` | 2.9 M (`index.html 85K`) | same; already isolated from Zig graph (`pages.yml` `bun run build` only) |
| Vendor duplication | `vendor/ui-kit:728K` + `site/vendor/ui-kit:728K` = 1.4 M duplicate | 728K single source if deduped to `file:../vendor/ui-kit` |
| Cache hit rate | flat module → any file change invalidates one large hash | layered modules → hit rate → 90 %+ for stable `kit`/`aikit` layers (per build-engineer checklist) |

No bundle-size or cold-build measurement was re-run for this design-only change; incremental figures are graph-hash reasoning, not wall-clock, per `build.zig:41-46` incremental cache design. Cold/WSL timings should be captured after Step 2 lands (add `zig build --time-report` or `hyperfine "zig build"` on macOS/Linux).

---

## 9. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `gtk.zig` vs `kit/ffi.zig` duplication (both declare GTK FFI, 229 vs 319 lines) | Keep `gtk.zig` in `core` initially, then merge into `kit/ffi.zig` as a follow-up; dedup frees one FFI surface to maintain. |
| `app_state.zig` god struct still central (`AppState:145` with 30+ widget refs) | Don’t move wholesale — keep in `core`, then incrementally delegate sidebar/search/status to `kit` callbacks (already underway per `docs/KIT.md` callback pattern). |
| Windows `build.zig:266-302` 11 libs linked per exe — forgetting to link for `metanoia-scraper` | `scraper_exe` links only `sqlite3`+`libc` (no GTK), so no Windows GTK chain needed; verify `zig build -Dtarget=x86_64-windows` still links `metanoia`’s 11 libs exactly as today. |
| `vendor/ui-kit` drift between `vendor/` and `site/vendor/` copies | Add `scripts/sync-ui-kit.sh` → `cp -r vendor/ui-kit site/vendor/ui-kit` or dedup to `file:../vendor/ui-kit`; CI `pages.yml` should assert `diff -rq vendor/ui-kit site/vendor/ui-kit` is empty if duplicate kept. |
| `data/db/*.db` shards not yet in version control | Ship `tools/bible/split_db.py` before changing `src/bible_db.zig:83-127` `ATTACH`; `openShardedDb()` falls back to `data/bible.db` if `manifest.json` missing (`docs/DB_SHARDING.md:80-84`). |
| `build.zig:41-46` cache does not guarantee cross-machine hits | Caching is per-machine `.zig-cache`; distributed caching via `sccache`/`build.zig` remote would be later (out of scope for this doc). |

---

## Checklist (per task)

- [x] Read `docs/DB_SHARDING.md`, `src/bible_db.zig`, `src/main.zig:1-1528`, `src/kit/root.zig:1-44`, `build.zig:1-448`, `mobile/` structure, `aikit/README.md`.
- [x] Produced volatility table with `file:line` + line counts, DB (`118M`) vs site (`site/out:2.9M`) contrast.
- [x] Drafted `build.zig` library splits: `kit` (stable) / `core` (bible_db+models+gtk+app_state) / `app` (main) / `services` (tts/llm) / `aikit` (`-Dnative-ai`).
- [x] Proposed split binaries: `metanoia` (main) + `metanoia-scraper` (standalone) + `site/out` (separate artifact) with `build.zig:41-46` graph DSL citation for isolated rebuilds.
- [x] Verified vendored `ui-kit`: `vendor/ui-kit/dist/*` (9 files, 728K) and `site/vendor/ui-kit/dist/*` (identical) exist; fixed `.gitignore:125-133` anchoring (`/vendor/*` + `!/vendor/ui-kit/**` + `!site/vendor/ui-kit/**` after `dist/`) so both are `git add --dry-run` addable and not swallowed by bare `vendor/` or `dist/`. `vendor/qwentts.cpp` stays ignored via `/vendor/*`.
- [x] No push (task: DO NOT PUSH). Changes reversible: `.gitignore` + this doc only.

---

*See also:* `docs/DB_SHARDING.md` (per-source DB volatility), `docs/KIT.md` (kit API), `docs/GEMINI.md` (build-engineer IO migration), `CLAUDE.md` (git safety + Zig nightly caveats).
