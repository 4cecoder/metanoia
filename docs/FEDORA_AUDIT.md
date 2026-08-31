# FedoraBible Clone Audit → Metanoia Upgrade Plan

Study of `https://github.com/cybertech99/FedoraBible` cloned to `/tmp/FedoraBible` (6 commits, Aug 26–27 2026, 1 star, 0 forks) vs Metanoia at `/Users/fource/bytecats/metanoia`. Goal: bury Masoretic deeper like Logos buries LXX (inverse), make Septuagint+GNT the primary study roots, and upgrade Metanoia's GitHub Pages for heavy developer onboarding.

> Clone is local at `/tmp/FedoraBible` — `ls -R /tmp/FedoraBible`, `cat /tmp/FedoraBible/README.md`, `cat /tmp/FedoraBible/data/sources/SOURCE.md` are the fastest way to follow along in this doc.
>
> **Companion:** `docs/SEPTCHECK_STEALS.md` covers the same study for `https://github.com/4cecoder/septcheck` at `/tmp/septcheck` (39 commits, FastAPI LXX+SBLGNT+Next.js) — the pure-Greek analysis engine to borrow depth from. Start here for Fedora's *app-is-the-site* and licensing; jump there for septcheck's search/analysis/MCP/forensic beats.

## 1. Executive Summary

Metanoia **already** does the inverse-Logos you want: `src/models/config.zig:86-96`, `src/models/config.zig:142` defaults `ot_source="lxx"`, `src/main.zig:403-417` pairs `LXX+E+LXXE( Brenton)`+`GNT` by default, and Masoretic is a single unchecked checkbox at the very bottom of `Settings` under `Advanced — Bible Tradition` `src/main.zig:1191-1213`. Mobile mirrors it `mobile/app/src/main/java/com/bytecats/metanoia/settings/SettingsManager.kt:123-134` default `septuagint`, `ReaderSettingsPage.kt:54` `ADVANCED — BIBLE TRADITION`.

FedoraBible is **not** Septuagint-first — it's 9-way neutral. Every tab picks its own translation from a dropdown, no primary. The interesting part to steal is *how* it ships interesting sources and *how* its GitHub Pages doubles as the app and its docs.

Plan below keeps your primacy (LXX+GNT first, MT buried even deeper) while cherry-picking Fedora's three wins: (a) Swete LXX Greek + Peshitta/Coptic/Van Dyck as *optional deep sources*, (b) import pipeline that makes adding a translation a one-liner, (c) Pages IA/design that actually onboards devs.

## 2. What Was Cloned & Where to Look

| Path | What it is | Live check |
|------|------------|------------|
| `/tmp/FedoraBible/README.md` | 9-translation table, setup, features, PWA gotchas | `cat /tmp/FedoraBible/README.md | head -n 300` |
| `/tmp/FedoraBible/data/sources/SOURCE.md` | Per-source licensing + import shape (146 lines) | `cat /tmp/FedoraBible/data/sources/SOURCE.md` |
| `/tmp/FedoraBible/data/schema.sql` | `translations/books/verses` + FTS5 + `tabs/highlights/notes/bookmarks/read_chapters` | `cat /tmp/FedoraBible/data/schema.sql` |
| `/tmp/FedoraBible/public/index.html` | The reader itself — also the GH Pages site (`public/` is the Pages publish dir) | `cat /tmp/FedoraBible/public/index.html | head -n 300` |
| `/tmp/FedoraBible/public/css/app.css` (942 lines) | Parchment/Manuscript/Ink 3-theme system, Inter+Literata, column paging | `cat /tmp/FedoraBible/public/css/app.css | head -n 400` |
| `/tmp/FedoraBible/public/js/*.js` (3238 lines total) | `tabs.js` linked-scroll, `reader.js` dual-column, `palette.js` Ctrl+K, `localDb.js` WASM SQLite | `ls -R /tmp/FedoraBible/src`, `wc -l /tmp/FedoraBible/public/js/*.js` |
| `/tmp/FedoraBible/scripts/*.js` | 4 importer shapes + Swete/Peshitta special cases, `books-meta.js`, `init-db.js` | `ls -R /tmp/FedoraBible/scripts` |

Metanoia counterparts to compare:

| Fedora | Metanoia | Note |
|--------|----------|------|
| `data/schema.sql` | `src/bible_db.zig:129-180` `init_db()` + `data/bible.db` (118 MB) | Metanoia has 82 books + `interlinear`/`lexicon`/`cross_references`, Fedora has 66 + `read_chapters`/`tabs` tables but no interlinear |
| `scripts/import-*.js` | `tools/bible/import_brenton_septuagint.py`, `migrate_add_interlinear_source.py`, `cache_lxx_interlinear.py`, `native_scraper.zig:315-738` | Fedora's pipeline is more modular/pluggable |
| `public/index.html`+`public/css/app.css` is the site | `index.html` (552 lines) Tokyo Night dev-portal only | Fedora's *app is its Pages site*; Metanoia's Pages is a separate dev portal |
| `.github/workflows/pages.yml` not present (deploys `public/` to GH Pages) | `.github/workflows/pages.yml:22-24` `path: .` serves repo root + `.well-known/assetlinks.json` | Metanoia serves entire root, Fedora serves built `public/` |

## 3. Schema Deep-Dive

### Fedora (`/tmp/FedoraBible/data/schema.sql`)

```sql
translations(code PK, name, language, year, is_public_domain, source_note)
books(id PK, ordinal UNIQUE, name UNIQUE, abbrev, testament CHECK(OT/NT), chapters)
verses(id PK, translation_code FK, book_id FK, chapter, verse, text, UNIQUE(translation_code, book_id, chapter, verse))
verses_fts VIRTUAL USING fts5(text, content='verses', tokenize='porter unicode61')
  + triggers that call strip_niqqud() — see src/db.js:stripNiqqud()
tabs(position, translation_code FK, book_id FK, chapter, is_active, font_family, font_size, view_mode, column_mode, linked)
highlights/bookmarks/notes keyed by (book_id, chapter, verse) — translation-independent
read_chapters(book_id, chapter) — journey progress
```

`strip_niqqud` removes Hebrew vowel points `[\u0591-\u05C7]` before FTS indexing so unpointed search matches pointed text. Reindexed in batches of 2000 in `scripts/init-db.js:reindexFts()` to avoid `database disk image is malformed` with large FTS tables.

### Metanoia (`src/bible_db.zig:148-180`)

```sql
verses(id PK, book TEXT, chapter INT, verse INT, text TEXT, version TEXT, footnotes TEXT)
  + UNIQUE INDEX idx_verse_lookup ON (book, chapter, verse, version)

interlinear(id PK, book, chapter, verse, word_index, original_text, translation, strongs, morphology, source TEXT NOT NULL DEFAULT '')
  + UNIQUE idx_interlinear_unique ON (book, chapter, verse, word_index, source)
  + INDEX idx_interlinear_source ON (book, chapter, verse, source)
  source = 'MT'|'LXX'|'GNT' — see comment src/bible_db.zig:158-165

lexicon(strongs PK, language, lemma, transliteration, definition, usage)
cross_references(from_book, from_chapter, from_verse, to_book, to_chapter, to_verse)
book_metadata, chapter_summaries
lib.highlights/lib.notes/lib.lexical_favorites in ATTACHED library.db (src/bible_db.zig:83-127) — survives content DB wholesale-replace on update
```

Metanoia has richer study layer (interlinear + lexicon + morphology + Strong's) and wider canon (82 entries `src/bible_db.zig:334-422` with `Canon.Protestant/Deuterocanon/Ethiopian` + `Testament.EthiopiaExpanded`), but no `translations` registry, no per-translation `book_ids`/`min_ordinal`/`max_ordinal` (Fedora's coverage-snapping in `public/js/tabs.js:snapToCoverage()`), and no `read_chapters` journey.

**Live DB stats (Metanoia):** `verses`: LXXE 27058 + NKJV 31102, `interlinear`: GNT 138994 + LXX 432676 + MT 233343, 118 MB `data/bible.db`.

**Takeaway for Septuagint primacy:** Metanoia's `get_verse_lexicon_context` `src/bible_db.zig:584-598` already prefers `ORDER BY source LIMIT 1` where `'GNT'<'LXX'<'MT'` lexicographically — OT prefers LXX over MT. Make it *exclusive* (no MT fallback unless opt-in) to fully root study in Greek.

## 4. Import Pipeline

### Fedora: 4 shapes + 1 special (`/tmp/FedoraBible/data/sources/SOURCE.md:130-146`)

| Script | Shape | Example | Used for |
|--------|-------|---------|----------|
| `scripts/import-translation.js` | One JSON per book + optional `Books.json` | `data/sources/kjv/*.json` `{book, chapters:[{chapter, verses:[{verse,text}]}]}` | KJV, PESH, COPS, PESHOT |
| `scripts/import-midvash.js` | One JSON per book, no Books.json, `englishName` field must match `books.name` | `data/sources/wlc/*`, `data/sources/tr/*` | WLC (Heb 23k), TR (GNT 7957) |
| `scripts/import-usfm.js` + `lib/usfm.js` | One `<CODE>.usfm` per book (`GEN`, `PSA`...) | `data/sources/lxx-en/*.usfm` (Brenton 39 books) | LXXE English — handles `\f/\x` footnotes, `\add/\sc` keeps text, 35a-letter suffixes fold |
| `scripts/import-pipedelim.js` | Single flat `NNS||chapter||verse||text` | `data/sources/vandyck-ar/vandyck.txt` (31k, RTL) | AVD Arabic |
| `scripts/import-swete.js` + `lib/swete.js` | One-word-per-line | `data/sources/lxx-gr/*.txt` (22k) | LXXG Greek — Latin `Regnorum_I`→`1 Samuel` map, skips Ezra/Nehemiah combined + missing Ecclesiastes |

All via `lib/import-core.js:runImport({code, name, language, year, isPublicDomain, sourceNote}, bookEntries)` → single `npm run setup` chains them `package.json:setup`.

### Metanoia

| Script | Shape | Source |
|--------|-------|--------|
| `tools/bible/import_brenton_septuagint.py:37-60` `BOOK_MAP` + `parse_chapter()` | Single zip `eng-Brenton_html.zip` → parses `PSA001.htm`/`GEN01.htm` via BeautifulSoup `span.verse` sentinel `\x00` | Brenton LXXE 27k verses `version='LXXE'` `src/bible_db.zig:154-155` |
| `tools/bible/cache_lxx_interlinear.py` | Scrapes `https://biblehub.com/interlinear/apostolic/{book}/{chapter}.htm` `source='LXX'` | Apostolic Polyglot interlinear 432k rows |
| `src/native_scraper.zig:315-738` `languagePrefix()`, `parseInterlinearHtml()`, `scrapeInterlinear()` | Scrapes `biblehub.com/interlinear` on-device, but `source` only `'MT'`/`'GNT'` `src/native_scraper.zig:734` — LXX only via Python path | Live interlinear/lexicon |
| `tools/bible/migrate_add_interlinear_source.py` | Migration adding `source` col, backfill `MT`/`GNT`, rebuild unique index | One-time |

Fedora's `books-meta.js` is the analogue of Metanoia's `BIBLE_BOOKS [82]` + `tools/bible_books.json` drift guard `src/bible_db.zig:504-533`.

**What to borrow:** Fedora's `language` tag driving RTL + font stack (`public/js/reader.js:languageOf()`, `fontChoicesFor()`, `RTL_LANGUAGES`, `fonts.css` with Noto Syriac/Coptic/Hebrew/Arabic) and coverage-snapping (`book_ids`/`min_ordinal`/`default_book_id` per translation).

## 5. GitHub Pages & PWA

### Fedora

- **Pages publish dir:** `public/` only — a no-build static site (`package.json` has no build step, just `esbuild`/`postject` for the optional `.exe`). Deploy `public/` to any static host (GH Pages, Cloudflare Pages). `npm run pwa:seed` copies `data/bible.db` → `public/data/bible.db` for the WASM SQLite seed.
- **PWA that *is* the app:** `public/sw.js` caches `data/bible.db` to OPFS via `@sqlite.org/sqlite-wasm` + `public/js/localDb.js`/`localDb.worker.js` (454 lines). First phone visit over HTTPS downloads ~55–63 MB DB once; subsequent visits run fully offline (`/api/*` never intercepted `public/sw.js:never intercepts /api/*`). HTTPS required — LAN `http://192.168.1.20:3000` fails on iOS, workaround `chrome://flags/#unsafely-treat-insecure-origin-as-secure` or `cloudflared tunnel`.
- **Reader is the page:** `public/index.html` — topbar with tab-bar/palette/theme/drawer, `panes` with linked-scroll,dual-column paginated e-book (64px gap, 280px min col, horizontal `scrollBy`/`scrollend` snapping), drawer with Search/Marks/Notes/Saved/Journey + Markdown export.
- **Design system:** `public/css/app.css:root` 3 themes via `data-theme` on `<html>` — Parchment `#f4efe4/#99502f`, Manuscript `#e9dcc3/#8a4a24`, Ink `#121110/#d9985f`; Literata serif + Inter UI; `kbd` styling, `::selection` accent glow, thin scrollbars, `chapterIn` 0.34s ease.

### Metanoia

- **Pages publish dir:** repo root `.` — `/.github/workflows/pages.yml:22-24` `path: .` uploads entire repo so `.well-known/assetlinks.json` is served for Android App Links. Site *is* `index.html` (552 lines) — a developer portal for deep linking, **not** the app itself.
- **No PWA:** The app is native (Zig/GTK4 desktop + Kotlin Android + iOS Swift). GH Pages only documents `metanoia://` and `https://metanoia.bytecats.codes/bible/...` links.
- **Design system:** `index.html:10-25` `:root` Tokyo Night (`--bg-primary:#0f1117`, `--accent:#7aa2f7`), `liquid-glass` backdrop-blur 20px, `Inter`+system serif. Sections: `How It Works` (3 cards HTTPS/Custom/Flexible), `Integration Guide` (Kotlin/Web/JS), `Link Examples` table, `Testing` ADB line, `FAQ` 4 cards (not installed/iOS/translations/deuterocanon), `Developer Resources` 3 cards.
- **Gap:** No onboarding path, no translation table, no architecture notes, no journey/search UI — a new dev lands on deep-link docs with no path to `zig build run` or `docs/MAINTENANCE.md`.

**What to borrow:** Fedora's *information architecture* (translations table, setup one-liner, features grid, data model diagram, PWA/HTTPS gotchas, import guide) and *micro-interactions* (copy buttons, toast, `?` shortcut map, `data-theme` toggle) — but keep Tokyo Night glass identity, not parchment.

## 6. Septuagint vs Masoretic: Current vs Desired

### Current Metanoia (already inverse-Logos)

- Default OT reads Greek: `Config.ot_source="lxx"` `src/models/config.zig:142`, Paired `preferred_version = LXXE else NKJV` `src/main.zig:417` and `preferred_source = LXX/GNT` `src/main.zig:404-407`, lexicon prefers LXX `src/bible_db.zig:588-590`.
- Masoretic is opt-in: checkbox `src/main.zig:1197-1201` labelled "Use Hebrew Masoretic Text" unchecked by default, in `Advanced — Bible Tradition` at bottom after TTS/LLM/Performance sections. Description `src/main.zig:1195` explicitly says "By default…Septuagint (LXX)…paired with GNT…"
- Interlinear fallback never hard-fails: SQL `ORDER BY (version != ?), version LIMIT 1` `src/main.zig:421-425` / `VerseDao.kt:27-42` — but the fallback is currently MT if LXX not cached for a chapter.

### Fedora (neutral)

- `WLC` (Heb MT 23,318 verses) and `LXXG` (Swete Greek 22,045 verses) are peers in the same dropdown per-tab; per-tab choice, no default. `WLC` renders RTL with Noto Serif Hebrew, `LXXG` with Gentium/Noto Serif Greek. Book picker filters to `book_ids` the translation actually has (so an OT-only text doesn't list NT).

### Desired (buried-MT, LXX+GNT as roots)

1. **Deepen the burial** (Logos-like): keep checkbox but add friction — move it from "Advanced" card to a secondary modal or collapsed `<details>`, require confirmation dialog "This will switch OT study to Masoretic…", and update every user-facing mention to call MT "comparison text" not default.
2. **Make roots exclusive:** when `ot_source=lxx`, queries should *not* fall back to MT — show a "Septuagint not yet cached for this chapter, tap to fetch" instead of silently serving MT. One-line change in `src/bible_db.zig:594-597` and `src/main.zig:501-527`.
3. **Add the interesting Greek sources as *deep* options, still under LXX:** import `nathans/lxx-swete` (CC BY-SA 4.0) into a new `LXXG` `verses` code alongside existing `LXXE` — exactly Fedora's split (`LXXE` Brenton English 27k, `LXXG` Swete Greek 22k). That's the "more Septuagint" Roger wants — now we have two LXX witnesses (Brenton + Swete) both Greek-rooted, not one.
4. **Interesting sources behind the same deep gate:** Peshitta NT (Syriac, 7,956, PD), Coptic Sahidic NT (7,933, CC BY-SA), Van Dyck Arabic (31k, PD) — all Fedora `data/sources/` already vendored at `/tmp/FedoraBible/data/sources/*` (12K–8.7M each). Ship them as unchecked `translations`-style alternatives or `is_public_domain` rows, not primary reading panes.

## 7. Proposed GitHub Pages Upgrade (Keep `/tmp/FedoraBible` Design Inspiration, Keep Tokyo Night)

### IA (inspired by Fedora `README.md`+`data/sources/SOURCE.md` structure, stays in single `index.html`)

```
Hero (keep current "Deep Link to Bible Verses" but add LXX-first tagline: "Greek OT+NT as one story")
→ How It Works (keep 3 cards)
→ Included Translations (NEW — Fedora's table, but LXX-first order)
      LXXE / LXXG (Swete) / GNT — "Primary Greek Roots" badge
      NKJV / WLC — "Comparison (Masoretic, buried)" muted
      Peshitta / Coptic / AVD — "Interesting Sources (optional)" muted
→ Quick Start for New Devs (NEW — Fedora's npm run setup analogue)
      zig build run (master nightly), brew/apt deps, android studio, zig env std_dir check
      60-sec clone→run, not 15-min archaeology
→ Architecture at a Glance (NEW — from docs/index.md+MAINTENANCE.md)
      src/kit | src/bible_db.zig lib split | aikit native | mobile/ | .well-known/app links
→ Data Model (NEW — Fedora's schema section)
      verses versioned, interlinear source='LXX'/'GNT'/'MT', lexicon, FTS5 niqqud-stripping
→ Integration Guide (keep, expand with ET: link to LXX vs MT verse numbers)
→ Link Examples (keep)
→ FAQ (expand from 4 to 10 — lift Fedora's HTTPS/PWA gotchas, translation licensing, canon 66→82)
→ Developer Notes (NEW — curated from docs/MAINTENANCE.md: caching bug postmortem, quick-wins backlog, signal safety)
→ Footer (keep)
```

### Visual polish to cherry-pick from `/tmp/FedoraBible/public/css/app.css`

- `kbd` style (`#kbd-bg`, `border-bottom-width:2px`) for `Ctrl+K`, `?`, `adb` blocks — currently plain `<code>` in Metanoia.
- Copy-button per code block (`public/js/app.js` clipboard + 2s "Copied!" toast) — Metanoia already has it, keep it.
- `toast` utility (`public/js/app.js:toast()`) for "Copied!" / theme switches.
- `literata`+`inter` font stack via `public/fonts/fonts.css` + `Noto` for Syriac/Coptic/Hebrew/Arabic when we add those translations — we already ship Tokyo Night fonts, add the 3 Noto families only when needed.
- Do **not** switch away from Tokyo Night (`--bg-primary:#0f1117`, `--accent:#7aa2f7`, `liquid-glass`) — that's brand. Just lift Fedora's spacing/radius/shadow scale.

### Workflow change

- Keep `.github/workflows/pages.yml:22-24` `path: .` (needed for `.well-known/assetlinks.json`). Don't switch to `public/`-only.
- Optionally add a build job that validates `index.html` links (`tidy`/`html-validate`) and that `data/sources/SOURCE.md` licensing table stays in sync with `data/bible.db` versions — Fedora has no build, we keep that check in CI.

## 8. Prioritized Implementation Order

**Phase 0 — Study (done, you're here).** Clone at `/tmp/FedoraBible` is available. No code changes yet per your "study first" choice.

**Phase 1 — Pages audit → plan → preview (next).** Write this audit (this file) + sketch new `index.html` IA in a branch, without merging. Preview via `python -m http.server` or GH Pages preview env. Effort: ~2–3 h, no DB changes, no licensing risk.

**Phase 2 — Bury MT deeper (no new data).** In `src/main.zig:onSettingsBtnClicked` move the Masoretic checkbox into a collapsed `<details>` or secondary dialog behind a "Show comparison texts" toggle, add confirm dialog, and change `src/bible_db.zig:get_verse_lexicon_context` to not fall back to MT when `ot_source=lxx` (show placeholder instead). Tests: `src/models/config.zig:35-47` + manual `data/config.json` `ot_source` roundtrip. Effort: ~1 h.

**Phase 3 — Add Swete LXXG as second LXX witness (the "more Septuagint").** Copy Fedora's `data/sources/lxx-gr/` (8.7M) + `scripts/import-swete.js` + `lib/swete.js` pattern into `tools/bible/` or reuse `import_brenton_septuagint.py` shape to import into `verses` as `version='LXXG'` (22k verses, CC BY-SA 4.0 — attribution + share-alike, unlike Brenton PD). Requires `versions` entry `LXXG` + schema unchanged (already multi-version). Large but safe. Effort: ~3–4 h including download/verify/attribution.

**Phase 4 — Interesting sources (opt-in, non-primary).** Any of `data/sources/peshitta` (Peshitta NT Syriac 7,956), `coptic-sahidic` (COPS 7,933), `vandyck-ar` (AVD 31k) via `scripts/import-translation.js`/`import-pipedelim.js` patterns. Each is `is_public_domain`/`language` tagged; Peshitta OT is **CC BY-NC** noncommercial — exclude from any commercial build or gate behind explicit consent. No change to default reading path. Effort: ~2 h per translation.

**Phase 5 — NIQQUD + FTS + journey.** Lift Fedora's `strip_niqqud()` for Hebrew search (`src`-side FTS on `verses_fts`) and `read_chapters`/`tabs` persistence if we want cross-device reading progress. Defer unless search complaints arise.

## 9. Licensing & Risk

- **Safe PD:** KJV (US PD, UK Crown caution), TR (Stephanus 1550/Scrivener 1894), WLC (free-distribution via tanach.us), LXXE Brenton 1851 PD, LXXG Swete text PD + transcription CC BY-SA 4.0 (requires attribution+share-alike — Fedora does this in `data/sources/SOURCE.md`+`source_note`), Peshitta NT (BFBS 1905/20 PD), Van Dyck 1865 PD.
- **Non-PD / flagged:** Peshitta OT `CC BY-NC` (Fedora flags it `is_public_domain=false` and warns to remove for commercial distribution), NKJV (copyrighted — Fedora explicitly excludes NIV/ESV/NKJV/NASB; Metanoia currently ships NKJV `data/bible.db` — consider replacing with WEB/YLT/ASV for public Pages builds).
- **Keep `.gitignore: /models/` anchored** — Fedora `data/` is 63M `bible.db` + ~30M sources; don't vendor model weights. Keep `data/bible.db` tracked with `!data/bible.db` exception as today.

## 10. Where to Verify Locally

```bash
# Fedora
cat /tmp/FedoraBible/README.md
cat /tmp/FedoraBible/data/sources/SOURCE.md
cat /tmp/FedoraBible/data/schema.sql
cat /tmp/FedoraBible/public/css/app.css | head -n 400
ls -lh /tmp/FedoraBible/public/data/bible.db      # ~63M
du -sh /tmp/FedoraBible/data/sources/* | sort -h

# Metanoia
grep -rn "ot_source\|masoretic\|septuagint\|preferred_source" src/ mobile/
cat docs/MAINTENANCE.md | head -n 100
sqlite3 data/bible.db "SELECT version, COUNT(*) FROM verses GROUP BY version"
sqlite3 data/bible.db "SELECT source, COUNT(*) FROM interlinear GROUP BY source"
```

## 11. Suggested Next Step (Awaits Your Go-Ahead)

You're on "study first" — so next is a preview branch that reworks `index.html` per §7 IA (no merge, no push without explicit ask per `CLAUDE.md` git safety) plus a follow-up ticket to implement Phase 2 (deepen MT burial). Say the word and I'll open that branch and draft the preview.
