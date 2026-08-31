# Septcheck Steals — What Metanoia Should Borrow from 4cecoder/septcheck

Clone at `/tmp/septcheck` (39 commits, Jul 2026, FastAPI + SBLGNT+LXX Swete + Next.js). This is the inverse of FedoraBible: pure Greek roots, no Masoretic at all — exactly the LXX+GNT primacy you want, plus a forensic analysis depth Metanoia and Fedora both lack.

## 0. Where to Look Live

```bash
cat /tmp/septcheck/README.md | head -n 250
cat /tmp/septcheck/docs/architecture.md | head -n 300
cat /tmp/septcheck/docs/database.md | head -n 250
cat /tmp/septcheck/docs/design-north-star.md | head -n 400
cat /tmp/septcheck/lxx_server.py | head -n 350
cat /tmp/septcheck/lxx_db.py | head -n 250
cat /tmp/septcheck/lxx_mcp.py | head -n 150
cat /tmp/septcheck/lxx_vectors.py | head -n 150
cat /tmp/septcheck/frontend/src/app/page.tsx | head -n 200
```

## 1. Why Septcheck Matters for the "Bury the Masoretic" Thesis

- **It *is* buried-MT taken to its logical extreme:** DB at `~/.cache/lxx_server/lxx.db` (`lxx_db.py:DB_PATH`) holds only `LXX` (Swete via `nathans/lxx-swete`) + `NT` (SBLGNT via `Faithlife/SBLGNT`) — zero WLC/MT rows. 37K verses (`verses_lxx` 29,957 + `verses_nt` 7,010 `README.md:health`). The NT *is* the SBLGNT Greek, not an English translation of MT.
- **Same Swete source as Fedora's LXXG:** both consume `nathans/lxx-swete` word-per-line `1.2.3 word` format (`lxx_db.py:_load_lxx_books()` via `_LXX_REF_RE`). If we import Fedora's `data/sources/lxx-gr/` into Metanoia's `verses version='LXXG'`, we share the same underlying Greek corpus septcheck uses for analysis — analysis and reading stay consistent.
- **Validates the product bet:** `docs/design-north-star.md:1` states the goal as "given any NT passage, produce the pastor-quality scene match — Mary Magdalene ↔ Joseph and brothers, Emmaus ↔ Elijah — with linguistic receipts." Every feature is scored against that gold set via `eval_gold_pairs.py`. That eval loop is exactly the heavy developer note + FAQ you want on GH Pages: a *numbered* evidence trail, not prose.

## 2. Architecture to Steal

### 2.1 Data layer (`lxx_db.py:597`, `docs/database.md`)

```sql
verses(id, testament LXX|NT indexed, book_id, book_name, chapter, verse, text, text_ascii)
  UNIQUE (testament, book_id, chapter, verse) — mirrors Metanoia's idx_verse_lookup
  text_ascii = greek_to_ascii(text) precomputed for fuzzy search

strongs_entries(strongs_num UNIQUE, unicode, ascii indexed, translit, definition, kjv, derivation, is_function_word)
semantic_fields(field_name indexed, word_ascii, source base|expanded)
citation_formulas(pattern, pattern_ascii, english_label, likely_book)
book_groups(group_name, book_name)
```

Warm-start: `_warm_build()` in `lxx_server.py:async _warm_build()` builds IDF vectors, n-gram index (2–5), Strong's verse index, similarity matrix, then pickles to `~/.cache/lxx_server/analysis/` via `lxx_analysis_cache.py`. Next launch loads in ~0.5s vs ~13s compute. Metanoia could reuse this pattern for `interlinear`+`lexicon` IDF without blocking UI (same `g_thread_new` background pattern already in `llm_engine.zig`).

**Steal:** add `text_ascii` alongside Metanoia's `verses.text`/`interlinear.original_text`, or compute on the fly via `lxx_translit.py:72 greek_to_ascii()` (handles rough breathings that currently cause `art`⊂`amart-` false positives — see `TODO.md: Known Issues #7`).

### 2.2 Search (`lxx_server.py` + `lxx_translit.py:72`, `frontend/src/lib/api.ts`)

- `GET /search?q=&k=&score=&t=&book=` and `POST /search` with JSON body, plus `GET /compare?q=&k=` side-by-side `{lxx:[], nt:[]}`.
- `rapidfuzz.fuzz.partial_ratio` over in-memory `verse_texts` ASCII index — accepts Greek Unicode *or* ASCII transliteration (`αγαπη` or `agaph` both hit). `?simple=true` returns pipe-delimited `LXX|Genesis|1|1|Ἐν ἀρχῇ…|score` for LLM token budgets.
- Metanoia's current search is FTS5 over English `verses.text` only; adding a Greek `partial_ratio` side would make the LXX actually *findable* by transliteration, not just by English gloss.

**Steal:** a new `GET /api/greek-search?q=` (or local `native_scraper.zig`-backed) that wraps `greek_to_ascii` + `rapidfuzz`, and a `simple` pipe format for LLM word-study context (cheaper than JSON for `llm_engine.zig` prompts).

### 2.3 Analysis suite (`lxx_analysis.py:1065`, `lxx_server.py` endpoints)

| Endpoint | What it does | Metanoia analogue today |
|----------|--------------|------------------------|
| `GET /analyze/allusion-scan?book=&c=&v_start=&v_end=&k=` | Rarity-weighted LXX allusions in an NT slice | none — flat `cross_references` |
| `GET /analyze/align?book_a&c_a&book_b&c_b` | Smith-Waterman word-level alignment, returns `aligned_a/b` + score | none |
| `GET /analyze/phrases?book&c&k&min_len&max_len` | n-gram extraction → LXX recurrence ranked by interestingness | none |
| `GET /analyze/semantic-fields?book&c&v_start&v_end` | Density of 17 fields (creation, covenant, sacrifice, judgment, salvation, kingship, temple, wisdom, prophecy, warfare, mercy, sin, deity, revelation, power, people, body) — `lxx_db.py:_SEMANTIC_FIELD_BASE` | none (lexicon definitions only) |
| `GET /analyze/tfidf?book&c&target_testament&k` | TF-IDF vector similarity vs target testament | none |
| `GET /analyze/citations?book&c&v_start&v_end` | Detects καθὼς γέγραπται / ἵνα πληρωθῇ formulas → LXX source | none |
| `GET /analyze/network?min_similarity&max_books` | Book similarity graph (vocab overlap) | none |
| `GET /analyze/report?book&c&v_start&v_end&k` | **Combined** — runs all above in parallel (`async`) | the study drawer would be this |
| `GET /analyze/typology` / `/analyze/forensics` / `/analyze/beat-scan` | Typological pattern, forensic linguistics, beat-sequence matcher (`lxx_beats.py:322` ordered beats + Smith-Waterman over 2-ch windows) | none |

`lxx_forensic.py:636`, `lxx_forensic_questions.py:1527` (7 composable questions), `lxx_beats.py:322` are the deep cuts: ordered beat-sequence matching was the only method that put Emmaus↔4 Kings 2 at #3, Zacchaeus↔Joshua at #3, baptism↔Joshua 3-4 at #6 where set-based scan ranked 0/14 `design-north-star.md: Cycle 4`.

**Steal (phased):**
- **Phase A (cheap):** `semantic-fields` 17-field dictionary + `citation_formulas` table — a static word-list, no ML. Add as `semantic_fields` table or JSON asset; surface as badges in the reader ("this chapter: 3× covenant, 2× sacrifice").
- **Phase B (medium):** `allusion-scan` + `phrases` + `tfidf` as a local sidecar (`uv run lxx_server.py` on `127.0.0.1:8000`, same machine as Metanoia's TTS/LLM sidecars). Metanoia's `llm_engine.zig` already fans out to Python/MLX sidecars — add septcheck as another.
- **Phase C (deep):** beat-sequence matcher for "Find LXX background for this NT verse" — the one-button flow from `design-north-star.md: One flow, progressive disclosure`. That's the heavy Pages demo: a live "NT → LXX scene" search that actually proves its hits with receipts.

### 2.4 MCP / LLM tool-use (`lxx_mcp.py:865`, `docs/mcp.md`)

```python
mcp = FastMCP("septcheck")
_ensure_backend() # auto-starts lxx_server.py subprocess on :8000 if not running
GET /tool-manifest → 6 OpenAI function definitions: get_verse, get_chapter, get_verses, get_range, search_verses, compare_testaments
```

Plus transliteration guide (`a=α b=β th=θ ph=φ ps=ψ ch=χ ō=ω`) so LLM can search with `agaph` without knowing Greek keyboard. Metanoia's `llm_engine.zig` currently shells to Ollama with hand-built prompts; adopting the same manifest means word-study prompts can call `search_verses(q="kuriov")` directly instead of hallucinating.

**Steal:** publish Metanoia's own `GET /.well-known/tool-manifest` (or at least document that a local septcheck on `:8000` exposes it), so any LLM client (Claude Desktop, Cody) can discover the Greek corpus without custom glue.

### 2.5 Vectors (`lxx_vectors.py:405`)

`paraphrase-multilingual-MiniLM-L12-v2` 384-dim, chunks 5 verses respecting book/chapter boundaries, `vectors/search` with `fmt=llm` citation blocks. `TODO.md: P5` notes vector pre-filter recall is the current bottleneck (only ~20 chapters get scored, gold often not among them) — still worth stealing as *supplemental* to FTS, not replacement.

### 2.6 Frontend interactions (`frontend/src/components/verse-context-menu.tsx` etc)

- `verse-context-menu.tsx` + `context-menu-provider.tsx` + `word-action-context.tsx` + `browse-verse.tsx`
- Right-click a **word**: Quick Lookup / Search in Corpus / Copy Word / Strong's G25 / Word Analysis / NKJV / Analyze — each opens `word-lookup-popup.tsx` or routes to `/typology`/`/forensics`.
- Right-click a **verse**: Copy Full / Copy Greek Only / Copy English Only / Show NKJV modal (`nkjv-modal.tsx` via `lxx_nkjv.py:175`) / Find Parallels → `/typology?book=&c=&v_start=`.
- Metanoia's reader (`src/kit/components/` + `src/ui/components/reader.zig:70` legacy) currently renders `verse` divs with no word-level hit-testing. Porting word spans + context menu is the smallest UI change with the biggest study payoff.

## 3. Frontend & Pages Design to Steal

Septcheck's Next.js app (`frontend/src/app/*`) is organized by *task*, not by endpoint:

```
browse/  — LXX|NT picker + chapter loader + NKJV toggle (page.tsx 200+ lines)
search/  — q input + k/score/testament filters, results with scores
search-demo/, verse-context-menu-demo/ — isolated component demos
forensics/, scenes/, typology/, sermons/ — each an analysis report viewer
```

Metanoia's Pages upgrade (`docs/FEDORA_AUDIT.md:7`) should mirror this: one page per study task (Browse Greek, Search, Scene Matches) rather than one page per DB table. The heavy dev onboarding lives in `docs/` — septcheck ships **4** heavy docs plus the north-star eval doc:

| Doc | What Metanoia should copy |
|-----|---------------------------|
| `docs/architecture.md` (file map + dep graph + data flow + design decisions) | Replace Metanoia's `docs/index.md:44` stub with same 3 diagrams; file map already exists in `docs/MAINTENANCE.md` but without graph. |
| `docs/database.md` (every table/col/index + in-memory indexes + disk cache invalidation via `db_stamp.txt` SHA) | Expand `src/bible_db.zig:129-180` comments into a real doc; document `library.db` split `src/bible_db.zig:83-127`. |
| `docs/api_reference.md` (every endpoint params + response JSON + `simple` variant) | Document `src/bible_db.zig` `verses`/`interlinear`/`lexicon` query shapes and deep-link scheme `docs/DEEP_LINKING_GUIDE.md:294`. |
| `docs/mcp.md` (MCP setup, tool table, transliteration guide, workflows) | New doc for `aikit/` + septcheck sidecar; transliteration guide belongs on Pages "Quick Start" alongside Zig nightly. |
| `docs/design-north-star.md` (eval harness, scoreboard, cycle log, known-noise ordering P1→P4) | The template for Metanoia's `docs/MAINTENANCE.md` quick-wins backlog — turn prose TODOs into measured `eval_gold_pairs.py`-style scoreboard. |

Next.js uses `shadcn/ui` (`components/ui/{badge,button,card,dialog,input,progress,scroll-area,select}.tsx`) — keep Metanoia's GTK `src/kit/` 12-file widget lib (`kit/widget.zig`, `kit/signal.zig`, etc. `docs/KIT.md`) as the desktop analogue, but mirror the *component inventory* (badge for Strong's, progress for warm-start, dialog for confirm-bury-MT, scroll-area for dual-column).

## 4. Concrete Borrow List (Prioritized for Metanoia's Two Tracks)

### Track A — Bury MT / Make LXX+GNT Roots Primary (no new deps)

1. **Adopt Swete as `LXXG` verses** (`/tmp/septcheck/lxx_db.py:_load_lxx_books()` source = same `nathans/lxx-swete` Fedora vendors at `/tmp/FedoraBible/data/sources/lxx-gr/` 8.7M). Add alongside Brenton `LXXE` — exactly Fedora's split, now backed by septcheck's proven loader.
2. **Add `text_ascii` + `greek_to_ascii` transliteration** (`lxx_translit.py:72`) so every Greek `verses.text` / `interlinear.original_text` is searchable as ASCII (`agaph` hits `αγαπη`). Eliminates the `art`⊂`amart-` collision class `TODO.md: Known Issues #7`.
3. **Semantic fields badges** (`lxx_db.py:_SEMANTIC_FIELD_BASE` 17 fields) as a static asset — cheapest "study root" signal, renders as tags in `load_chapter_into_study` `src/main.zig:388-571`.
4. **Word-level context menu** (`frontend/src/components/verse-context-menu.tsx` inventory) ported to GTK label spans — Quick Lookup (lexicon), Strong's, Copy Greek, Find LXX Parallels.

### Track B — Deep Study (add septcheck as local sidecar, same pattern as TTS/LLM)

5. **`?simple` pipe format** for LLM word-study prompts (`lxx_server.py` plain-text branch) — cuts token budget vs JSON when `llm_engine.zig` injects verse context.
6. **Sidecar `lxx_server.py` on :8000** for `/analyze/report` (combined) + `/search`/`/compare` — no DB duplication, just `lxx_mcp.py`-style `_ensure_backend()` probe from `llm_engine.zig`. Start with `simple=true` so results are pipe-delimited citations `lxx_vectors.py:format_citation()`.
7. **`GET /tool-manifest` → Metanoia Pages** — document that a local septcheck exposes the 6-function manifest; Metanoia's deep links (`metanoia://bible/John/3/16`, `https://metanoia.bytecats.codes/bible/jn/3/16` `index.html:324-358`) can then deep-link *with* `?t=LXX` variant.

### Track C — Heavy Pages Onboarding (copy septcheck's docs + Fedora's reading polish)

8. **New `docs/architecture.md` + `docs/database.md` + `docs/mcp.md`** modeled on septcheck's 3 heavy docs, content sourced from `docs/MAINTENANCE.md`, `docs/ZIG_DISCOVERIES.md`, `docs/GEMINI.md`, `docs/SIGNAL_SAFETY.md`.
9. **Single-flow "Find scene matches" demo** (`design-north-star.md: One flow, progressive disclosure`) as the GH Pages hero: paste NT passage → ranked LXX scene candidates with receipts + gold-set badge + expand to per-verse Greek parallels. That's the Fedora `public/index.html` *is-the-reader* idea, but for study.
10. **Eval scoreboard on Pages** (`eval_gold_pairs.py` → `docs/design-north-star.md:improvement cycle`) — publish typology recall 12/14, beats MRR 0.110, holdout predictions (John 8→Susanna #8, John 4→Gen 23-24 well) as living QA, not marketing.

## 5. What *Not* to Steal

- **The monolith `lxx_server.py:2687` itself.** `TODO.md: Priority 2` flags it as the top split target (>500 lines). Borrow its *endpoints* and *indexes*, not its file structure.
- **SQLite-via-SQLAlchemy + inline `uv run --script` header** — Metanoia is Zig + `libsqlite3` with a `std.atomic.Mutex` spin-lock `src/bible_db.zig:24-34` because `SQLITE_THREADSAFE=2`. Keep the Zig-native mutex model; don't add Python SQLAlchemy to the desktop path.
- **The 65-detector corpus-wide grep UI** — `design-north-star.md: Detectors are evidence, not results` demotes it behind a power-user affordance. Don't surface it as a top-level page; it overwhelmed septcheck's own nav (6 pages + 3 overlapping modes).

## 6. Suggested Next Edit (Still No Push Without Explicit Ask per CLAUDE.md)

Phase 0 study now covers both clones. Next step is a preview branch that:
- extends `docs/FEDORA_AUDIT.md:11` plan with this file's Track A items 1–4 (no Python dep),
- drafts `index.html` IA from `FEDORA_AUDIT.md:7` but adds septcheck's `/?simple` and tool-manifest callouts,
- opens `docs/architecture.md` stub from `septcheck/docs/architecture.md` file-map template.

Say go and I open that branch.
