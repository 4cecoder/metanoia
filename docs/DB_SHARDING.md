# DB Sharding — Breaking Up the 118 MB Monolith

**Status:** design — migration script ships next, Zig ATTACH layer is backward-compatible with `data/bible.db`.

## Problem

`data/bible.db` (118 MB) is one SQLite file holding **everything**:

| Table | Rows | What | Primacy |
|-------|------|------|---------|
| `verses` `version='LXXE'` | 27,058 | Brenton English LXX (1851) — **primary OT English** | PRIMARY |
| `verses` `version='NKJV'` | 31,102 | NKJV — **Masoretic English, copyrighted** | BURIED |
| `interlinear` `source='LXX'` | 432,676 | Apostolic Polyglot — **primary OT Greek** | PRIMARY |
| `interlinear` `source='GNT'` | 138,994 | SBLGNT-ishish — **primary NT Greek** | PRIMARY |
| `interlinear` `source='MT'` | 233,343 | WLC-derived — **buried** | BURIED |
| `lexicon` | 6,338 | Strong's | SHARED |
| `book_metadata` / `chapter_summaries` / `cross_references` | 5 / 3 / 0 | Canon registry | CORE |
| `versions` | 2 | `LXXE`+`NKJV` | CORE |

- One `git pull` rewrites 118 MB even if only one source changed.
- Shipping NKJV (copyrighted) in the default bundle is a licensing liability — FedoraBible (`/tmp/FedoraBible/data/sources/SOURCE.md:1` "NIV/ESV/NKJV/NASB are not" PD) buries it correctly; we ship it as primary-OT-English fallback.
- The Masoretic shard **should not be in the default bundle at all** if LXX+GNT are the roots — but today you can't exclude it without rebuilding the whole file.
- Mobile `mobile/app/src/main/assets/bible.db.gz` copies the monolith blindly.
- Future “interesting sources” (Peshitta 7,956, Coptic 7,933, Van Dyck 31k — `/tmp/FedoraBible/public/data/bible.db:63M` keeps all in one file too) would make the file grow without bound.

Septcheck avoids this by keeping a **separate cache per index** (`~/.cache/lxx_server/analysis/lxx_idf.pkl` etc., `lxx_analysis_cache.py`) and Fedora keeps **separate source dirs** (`data/sources/kjv/*.json`, `lxx-gr/*.txt`) before merge. We keep the merge — but at the **file** level.

## Target Layout — Extremely Well Split

```
data/
  bible.db              # LEGACY monolith — kept as fallback until migration lands
  db/
    manifest.json       # shard registry (see below) — single source of truth
    core.db             # ~100 KB — versions, book_metadata, chapter_summaries, cross_references, books cache
    verses.lxxe.db      # ~18 MB — version='LXXE' (Brenton) — PRIMARY OT English
    verses.web.db       # ~20 MB — version='WEB' (World English Bible, PD) — replaces NKJV as comparison
    verses.kjv.db       # ~20 MB — version='KJV' (1769, Crown caution) — optional archaic peer
    interlinear.lxx.db  # ~38 MB — source='LXX' (Apostolic Polyglot) — PRIMARY OT Greek
    interlinear.gnt.db  # ~12 MB — source='GNT' — PRIMARY NT Greek
    interlinear.mt.db   # ~22 MB — source='MT' — BURIED, not in default bundle
    lexicon.db          # ~2 MB  — lexicon (language-indexed)
    fts.db              # ~8 MB  — FTS5 indexes (generated, not shipped in git; rebuilt per shard)
  library.db            # → NOT here — lives in app-support dir via bible_db.zig:userDataDbPath()
  ```

**Each shard is a fully valid SQLite file** with its own `CREATE TABLE` + indexes (same DDL as `src/bible_db.zig:148-180` but subset). A clean `VACUUM` per file.

### manifest.json

```json
{
  "version": 1,
  "generated": "2026-08-31T00:00:00Z",
  "shards": [
    { "file": "core.db",            "schema": "core",  "tables": ["versions","book_metadata","chapter_summaries","cross_references"], "primacy": "core" },
    { "file": "verses.lxxe.db",    "schema": "en_lxxe","filter": "verses.version='LXXE'",  "primacy": "primary", "license": "PD (Brenton 1851)", "source": "eBible.org/eng-Brenton_usfm.zip" },
    { "file": "verses.web.db",     "schema": "en_web","filter": "verses.version='WEB'",   "primacy": "comparison", "license": "PD (WEB, ebible.org)", "replaces": "NKJV" },
    { "file": "interlinear.lxx.db","schema": "el_lxx","filter": "interlinear.source='LXX'", "primacy": "primary", "license": "Apostolic Polyglot via biblehub scrape" },
    { "file": "interlinear.gnt.db","schema": "el_gnt","filter": "interlinear.source='GNT'", "primacy": "primary", "license": "SBLGNT-adjacent" },
    { "file": "interlinear.mt.db", "schema": "he_mt","filter": "interlinear.source='MT'",  "primacy": "buried", "license": "WLC Free via tanach.us", "bundle": false },
    { "file": "lexicon.db",        "schema": "lex",   "tables": ["lexicon"],               "primacy": "shared" },
    { "file": "verses.kjv.db",     "schema": "en_kjv","filter": "verses.version='KJV'",   "primacy": "optional", "license": "PD (US), Crown (UK)" }
  ],
  "default_bundle": ["core.db","verses.lxxe.db","interlinear.lxx.db","interlinear.gnt.db","lexicon.db"],
  "notes": "NKJV shard intentionally absent — replaced by WEB/KJV PD English. See learn/english."
}
```

- `primacy` drives **what ships by default** and what the site's `Learn → Canon` badges show (`Primary` vs `Comparison` vs `Buried`).
- `bundle:false` means the file is downloadable on demand (Settings → Advanced) but not in the default `zig build` / mobile asset.
- `filter` is the migration predicate — the script enforces it.

## How Zig Opens It

`src/bible_db.zig` already has the pattern (`attachLibraryDb()` at `src/bible_db.zig:83-127` for `library.db`). Extend it:

```zig
// Pseudocode — backward compatible
pub fn openShardedDb(allocator, io) !*sqlite3 {
    // 1) Try data/db/manifest.json -> for each shard in default_bundle ATTACH DATABASE 'data/db/<file>' AS <schema>
    // 2) If manifest missing, fall back to single data/bible.db (legacy) — so existing checkouts still run
    // 3) init_db() creates tables in their owning schema (core.lex vs en_lxxe.verses etc.) if shard file was empty
}

// Reads route by version/source via schema-qualified UNION ALL:
//   SELECT text FROM en_lxxe.verses WHERE book=? AND chapter=? AND version='LXXE'
//   UNION ALL SELECT text FROM en_web.verses WHERE ... — but callers that pass version='LXXE' only hit en_lxxe
// Lexicon stays cross-schema: SELECT ... FROM el_lxx.interlinear JOIN lex.lexicon
// FTS index lives in fts.db ATTACHed as fts, or rebuilt lazily per shard
```

Already verified `SQLITE_THREADSAFE=2` mutex (`src/bible_db.zig:24-34`) works across ATTACHed schemas — same connection, one mutex.

## Migration — No Data Loss

`tools/bible/split_db.py` (ships next):

```
python tools/bible/split_db.py --source data/bible.db --out data/db/ --manifest data/db/manifest.json
# 1) Creates data/db/*.db with same schema (VACUUM INTO)
# 2) For each shard, DELETE FROM verses/interlinear WHERE NOT (filter) — then VACUUM to shrink
# 3) Writes manifest.json with row counts + sha256
# 4) Leaves data/bible.db untouched — new code prefers shards if present
```

`tools/bible/join_db.py` does the reverse for packaging that still wants one file (e.g., `bible.db.gz` legacy).

## Build & Packaging Deltas

| Task | Before | After |
|------|--------|-------|
| `tools/bible/import_brenton_septuagint.py` | writes to monolith `verses` | writes to `data/db/verses.lxxe.db` only (`ATTACH` or direct open) |
| `tools/bible/cache_lxx_interlinear.py` | writes to monolith `interlinear` | writes to `data/db/interlinear.lxx.db` |
| `tools/bible/migrate_add_interlinear_source.py` | one-file ALTER | per-shard, but only needed once — shards already have `source` |
| `zig build run` | needs 118M `data/bible.db` | needs only 5 default shards (~70 MB) — MT not downloaded |
| `mobile/app/src/main/assets/bible.db.gz` | gz of monolith | gz of `core+en_lxxe+el_lxx+el_gnt+lex` bundle (generated by `tools/bible/export_android_asset.py` updated) |
| `aikit/README.md` `vendor/` rule | `/models/` anchored | add `data/db/*.db` per-file `.gitignore` with `!data/db/core.db` etc. but allow `!` per shard — or ship shards via release asset not git |

## Site — Where This Shows Up

- `site/src/app/docs/database/page.tsx` — shard diagram (this doc's table) + `manifest.json` viewer.
- `site/src/app/learn/english/page.tsx` — NKJV trap + Roger's PD English table (this motivates WEB replacing NKJV).
- `site/src/app/learn/canon/page.tsx` — badges `Primary/Comparison/Buried` map to `manifest.primacy`.
- `src/kit` docs: `docs/KIT.md` untouched — sharding is `bible_db.zig`, not `kit`.

## Decision Log

- **Why per-version/per-source files, not per-testament:** LXX+GNT are Greek roots across both testaments; splitting by testament would re-merge Greek across files. Per-source keeps Greek together, Hebrew buried cleanly.
- **Why keep fts.db separate:** FTS indexes are derivable (like septcheck's `analysis/` pickle cache) and large. Rebuilding per shard avoids reindexing all translations when one changes.
- **Why not follow Fedora's single `bible.db` (63M) or septcheck's single `lxx.db` (33M):** Both are fine for single-language web/PWA. Metanoia ships 3 source languages + 2 English recensions + user data durability (`library.db` outside bundle) — monolithic rewrites everything on any import.

## Next Steps

1. Land `tools/bible/split_db.py` + `manifest.json` (no behavior change yet).
2. Add `openShardedDb()` alongside existing `sqlite3_open("data/bible.db")` with fallback.
3. Add `tools/bible/import_web.py` (or reuse Fedora's `import-translation.js` shape via `import_web_usfm.py`) to populate `verses.web.db` — then `docs/learn/english` can point to a live shard instead of a plan.
4. Update `mobile` asset export + `.github/workflows/pages.yml` (site build already exports `site/out`).
