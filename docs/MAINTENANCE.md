# Maintenance Notes — 2026-07-19 session

What changed this session, why, what's still open, and how we intend to keep
this codebase easy to work on going forward. For Zig API specifics, see
[ZIG_DISCOVERIES.md](ZIG_DISCOVERIES.md) and [GEMINI.md](GEMINI.md) — this
doc is about the caching architecture, the testing strategy, and what's next.

## Direction as of this session

- **Windows is deprioritized.** `windows_helper/`, `ci/*msys*`, and
  `.github/workflows/release.yml` are untouched and left working, but no new
  effort goes there for now.
- **Focus: macOS + Linux desktop (GTK4/Zig) and the Android (Kotlin) client.**
  TDD + regression tests + CI enforcement on both.

## The original-language caching bug (why "verses aren't cached" happened)

Original-language (Hebrew OT / Greek NT) interlinear + lexicon data is
scraped from BibleHub by two Python scripts (`tools/bible/interlinear_scraper.py`,
`tools/bible/lexicon_scraper.py`) run as subprocesses from
`src/scraper_client.zig`, triggered once from `src/services/llm_engine.zig`
when a verse has no cached lexicon context yet. Three independent bugs
combined to make this "just sometimes doesn't work, silently, forever":

1. **Language-prefix drift.** The Python scraper had its own hardcoded
   Old-Testament book list, independent of `src/bible_db.zig`'s canonical
   `BIBLE_BOOKS`. It said `"Song of Solomon"` (with a space); the app always
   passes `"SongofSolomon"` (no space) — never matched, so that book (and
   every deuterocanonical/Ethiopian-canon OT book: Tobit, Judith, Sirach,
   Wisdom, Enoch, Jubilees, 1-3Meqabyan, Tegsas) silently got tagged Greek
   ("G") instead of Hebrew ("H"). **Fixed** by generating
   `tools/bible_books.json` from `BIBLE_BOOKS` (one-time, checked in) and
   having the scraper load it instead of its own list, plus a Zig test
   (`bible_db.zig`: `"BIBLE_BOOKS testament data matches tools/bible_books.json"`)
   that fails the build the moment the two ever diverge again.
2. **Silently swallowed failures.** `scraper_client.zig` discarded the
   subprocess exit code entirely (`_ = try child.wait(engine)`), and
   `llm_engine.zig` wrapped every scrape call in `catch {}`. A crashed or
   network-failed scrape looked identical to "nothing to cache yet" — no
   error, no retry signal, and the next click just repeated the same
   failure forever. **Fixed**: `scraper_client.zig` now checks
   `term.success()` and returns `error.ScraperFailed`; `llm_engine.zig`
   surfaces that failure via the existing `onStep` callback instead of
   swallowing it, and skips the (expensive, whole-DB) lexicon backfill pass
   when the interlinear fetch itself failed.
3. **No HTTP timeout, bare `except:`.** `interlinear_scraper.py` had no
   try/except around `requests.get` at all; `lexicon_scraper.py` had a bare
   `except:` with no timeout. A hung BibleHub response hung the subprocess
   (and thus the blocking `child.wait`) indefinitely. **Fixed**: both now
   set `timeout=15` and catch `requests.RequestException` specifically,
   exiting non-zero (interlinear) so Zig's exit-code check can see it.

The Android client (`mobile/`) had the *same bug class* via a different
mechanism: `BibleConstants.kt`'s book list has a third testament bucket,
`"Eth"`, that the old prefix logic didn't handle — it checked
`testament == "New"` and defaulted everything else (including `"Eth"`) to
Hebrew. Fixed with a single `strongsLanguagePrefix()` source of truth in
`BibleConstants.kt`, plus the same "swallowed failure" bug
(`catch (e: Exception) { Log.e(...) }` with no user-visible signal), fixed
by propagating exceptions and adding a `scrapeError` state + retry affordance
in the UI. See git history for the full diff.

### A related gap, fixed proactively

`init_db()` in `bible_db.zig` only ever created `highlights`/`notes`/
`book_metadata`/`chapter_summaries`/`lexical_favorites` — the tables that
actually hold cached data (`interlinear`, `lexicon`, `verses`,
`cross_references`) only existed because the *shipped* `data/bible.db`
happened to have them already. A freshly created database would be missing
those tables entirely, and a missing table looks exactly like "no rows yet"
to every read function here (`sqlite3_prepare_v2` just fails and the
function falls through to its empty/not-found default) — the same silent-gap
shape as the caching bug itself. `init_db()` now creates all of them with
`CREATE TABLE IF NOT EXISTS`, matching the real schema exactly.

### A real concurrency bug this surfaced, not just a hypothetical

While adding a regression test that fires several threads at a shared
`bible_db` connection (see below), the test **reliably SEGV'd**. Root cause:
the system libsqlite3 linked here is commonly compiled
`-DSQLITE_THREADSAFE=2` ("multi-thread" mode), which explicitly forbids
using the *same connection* from more than one OS thread concurrently —
and `llm_engine.zig` does exactly that via `g_thread_new` against the one
`state.db` connection opened in `main()`. Fixed with a small mutex around
every `bible_db.zig` public function (see
[ZIG_DISCOVERIES.md](ZIG_DISCOVERIES.md#stdthreadmutex-disappeared-0170-dev1422e863bf3be)
for why it's a hand-rolled atomic spinlock rather than `std.Thread.Mutex`,
which no longer exists in this Zig nightly). This was a real crash risk in
the shipped app any time two background operations touched the db at once
— now it's a passing regression test instead.

## Testing strategy: high-signal, not exhaustive

The ask was "regression testing... to drive stability yet ease of
maintaining" — not maximum test count. The rule we followed, and should
keep following:

**One test per bug class, not per function permutation.** Every test added
this session maps to something that was either (a) a real bug we just
fixed, or (b) a function that sits directly on the caching hot path and had
*zero* coverage before. We did not add exhaustive property tests, fuzzing,
or a test for every getter's every edge case.

- **`bible_db.zig` round-trip tests** use `sqlite3_open(":memory:")` — no
  fixtures, no network, no shared state, sub-second. This is the model for
  any new DB function: a "missing" case + a "round-trips after write" case,
  nothing more.
- **The drift-guard test** (`bible_books.json` vs `BIBLE_BOOKS`) is the
  template for "prevent this exact bug class from coming back" — cheap,
  and it directly encodes the lesson learned rather than re-testing generic
  JSON parsing.
- **The concurrency test** (`"concurrent writers on a shared connection
  don't corrupt or drop data"`) is deliberately singular — it's the pattern
  to extend if a *new* function starts being called from a background
  thread, not something to duplicate per-function. Real OS threads, no
  mocking, asserts on the actual data afterward rather than just "didn't
  crash."
- **`scraper_client.zig` tests** use real subprocesses (`/bin/sh -c "exit
  0/1"`) instead of mocking `std.process` — faster to write, and it
  actually exercises the `Term`-union logic rather than a hand-maintained
  fake of it.

**What "E2E" means for this app in practice.** Driving the real GTK UI
headlessly (fake X server / accessibility-tree automation) is heavy, flaky,
and — for a project this size — low payoff, because the business logic that
actually breaks (SQL, subprocess handling, language-tagging, concurrency)
lives below the GTK layer, not in it. What we're calling "E2E" here is
boundary-level integration testing of the real chain
(`scraper_client` → subprocess → sqlite) with GTK excluded, which is where
the bugs actually were. If a future feature's correctness genuinely lives
in GTK widget behavior (not just "does this button call this function"),
that's the point to reconsider a real UI-driving harness — not before.

**CI enforcement.** Neither `release.yml` nor `release-unix.yml` ever ran
the test suite — they only build release artifacts on a tag push, so tests
added alongside a change were never actually checked anywhere. Added
`.github/workflows/test.yml`: `zig build test` on macOS + Linux, and
`gradlew testDebugUnitTest` for the mobile client, on every push/PR. This is
the thing that makes "we wrote a regression test" mean "it's enforced,"
not just "it exists on someone's machine."

## Native-Zig scraper: eliminating the Python subprocess (in progress)

Follow-up to the caching-bug section above: `src/scraper_client.zig`'s
`scrape_interlinear`/`scrape_lexicon` no longer shell out to
`uv run python tools/bible/interlinear_scraper.py`/`tools/bible/lexicon_scraper.py` —
they call a native Zig port, `src/native_scraper.zig`, directly. (`tools/bible/scraper.py`,
the separate verse-text scraper reachable via `scrape_verses`, is untouched —
out of scope for this pass.) `tools/bible/interlinear_scraper.py`,
`tools/bible/lexicon_scraper.py`, and `tools/bible/scraper_common.py` are left in place
(nothing else references them, and removing them wasn't asked for) but are no
longer invoked by the app.

**What's in `native_scraper.zig`:**
- A small hand-rolled HTML tag/class scanner (`findElement`/`findElementById`
  + a depth-aware close-tag matcher, needed because BibleHub nests a plain
  `<table>` inside each Hebrew `tablefloatheb` word cell) — not a general
  parser, just enough to replicate BeautifulSoup's `.find()`/`.find_all()`
  calls in the Python scrapers.
- `parseInterlinearHtml` / `parseLexiconHtml` — pure functions (`[]const u8`
  in, no `std.Io`), so they're unit-tested against fixture strings with zero
  network access, per the brief's TDD preference.
- `fetchWithRetry` — mirrors `tools/bible/scraper_common.py`'s `fetch_with_retry`
  exactly: 3 attempts, 1s/2s/4s backoff, retries timeout/connection-failure/5xx,
  does not retry 4xx. The real per-attempt 15s timeout is implemented via
  `std.Io.Select` racing the fetch against a timer and canceling the loser —
  the closest native equivalent to `requests.get(..., timeout=15)` available
  in this Zig nightly (`0.17.0-dev.1422+e863bf3be`).
- Four new small `bible_db.zig` functions (`insert_interlinear_word`,
  `insert_lexicon_entry`, `lexicon_has_strongs`, `distinct_interlinear_strongs`)
  so the scraper's DB writes go through the existing `lockDb()`/`unlockDb()`
  mutex (see "A real concurrency bug this surfaced" above) instead of hitting
  sqlite3 directly. These use real parameterized binds
  (`sqlite3_bind_text`/`sqlite3_bind_int`, newly declared) rather than this
  file's existing string-interpolated-SQL pattern, since scraped web text can
  contain single quotes that would corrupt an interpolated query — this
  actually matches the Python side more closely, since its
  `cursor.execute(sql, params)` calls were already parameterized.

**Known behavioral notes (preserved from the Python originals, not fixed —
see native_scraper.zig's docstring and inline comments for detail):**
1. On today's live BibleHub markup, Hebrew (`tablefloatheb`) word tables use
   `class="strongsnt"` for their Strong's-number span, not `class="pos"`/
   `class="strongs"` like Greek tables — so `tools/bible/interlinear_scraper.py`'s
   (and this port's) `find(class_=["pos","strongs"])` never matches for
   Hebrew, and OT strongs numbers come back empty on a fresh scrape. Same gap,
   same class list, both languages. (Confirmed by fetching a real page,
   `curl -A "Mozilla/5.0" https://biblehub.com/interlinear/obadiah/1.htm`.)
2. `tools/bible/lexicon_scraper.py`'s `scrape_strongs()` only populates `definition`
   (and only if the page has `class="strongs"` and/or `class="strongsnt"`
   elements it never finds on today's real `/greek/N.htm`/`/hebrew/N.htm`
   pages); `lemma`/`transliteration`/`usage` are dead code, always `""`.
   Confirmed against the shipped `data/bible.db`: **all 6190 existing lexicon
   rows already have empty lemma/transliteration/definition/usage** — this
   isn't a regression, the feature has been a no-op against the live site for
   a while. Ported faithfully rather than silently "fixed", since guessing at
   better selectors would be a bigger behavioral deviation than preserving a
   documented no-op — fixing the actual extraction (real BibleHub lexicon
   page selectors) is a good follow-up but is a product/scope decision, not a
   silent side effect of a subprocess-elimination task.
3. No NFC Unicode normalization. The Python scraper does
   `unicodedata.normalize('NFC', text)` on original-language text; Zig's
   standard library has no built-in Unicode normalizer and hand-rolling one
   was out of scope. In practice BibleHub's Greek text is raw UTF-8 (not
   entity-encoded) and its Hebrew text is decimal-entity-encoded — untested
   whether either ever arrives in a form NFC would actually change, but this
   is a known, disclosed gap, not a verified non-issue.
4. `fetchWithRetry`'s "is this error worth retrying" gate
   (`isPermanentFetchError`) is a hand-picked allowlist of Zig errors
   (`UnsupportedUriScheme`/`UriMissingHost`/`InvalidHostName`) standing in for
   Python's `except (requests.Timeout, requests.ConnectionError)` vs "other
   `RequestException` subtypes propagate immediately" distinction — the two
   error taxonomies don't line up 1:1, so this is a reasonable approximation,
   not a literal port.

**Testing status:** `zig build test` passes clean (42 fixture/unit tests: HTML
parser against captured-real-page fixtures, retry-driver tests via a fake
attempt function, `bible_db.zig` round-trip tests for the four new
functions — all network-free, per the brief's preference for separating
parse-from-fetch over standing up a fake HTTP server). A
`METANOIA_LIVE_SCRAPER_TEST=1 zig build test` run against the real
`https://biblehub.com/interlinear/philemon/1.htm` (chosen for being short)
confirmed real-world, non-fixture behavior:
`LIVE interlinear: 141 distinct strongs numbers cached for Philemon 1` and
`LIVE lexicon sample: strongs=G3972 language=greek lemma="" definition=""` —
the empty lemma/definition on the very first live-fetched lexicon entry is
*expected*, not a bug: it's exactly known-behavioral-note 2 above, confirmed
live rather than just inferred from `data/bible.db`'s existing rows.

**Next-session TODO:**
- Consider whether `tools/bible/interlinear_scraper.py`/`lexicon_scraper.py`/
  `scraper_common.py` should now be deleted, since nothing in the app invokes
  them anymore (kept for this pass only because deleting wasn't explicitly
  asked for).
- Item 2 above (lexicon extraction being a near-total no-op against the real
  site) is the highest-value real follow-up — the feature exists end-to-end
  (fetch → parse → cache → read) but the parse step currently can't find real
  data on today's BibleHub markup. Needs someone to look at a real
  `/greek/N.htm` page and find the actual current selectors for
  lemma/transliteration/definition/usage, in both Python and this Zig port
  simultaneously so they don't drift again.
- The `std.Io.Select`-based per-attempt timeout (`httpGetOnce` in
  `native_scraper.zig`) is the first use of `Io.Select`/`Io.async` in this
  codebase — worth a [ZIG_DISCOVERIES.md](ZIG_DISCOVERIES.md) entry once it's
  been exercised more (the live test above is the first real-network
  exercise of it).

## Quick-wins backlog (noticed, not fixed — scoped out to avoid creep)

- ~~`get_chapter_verses` ignores the `version` column.~~ — **fixed
  2026-07-20**: the query now takes an explicit `version: []const u8`
  parameter and filters `WHERE version='{s}'` (`bible_db.zig`). There's
  still no app-wide "currently selected translation" concept (checked
  `config.zig` and every call site — nothing tracks one), so a
  `bible.DEFAULT_VERSION` constant (`"NKJV"`) was added as the minimal
  stand-in and is what `llm_engine.zig`'s one call site passes today. A
  regression test (`"get_chapter_verses: filters by version instead of
  mixing translations"`) inserts two versions of the same book/chapter/verse
  and asserts each `version` argument returns only its own rows. The real
  follow-up, if a second translation is ever actually loaded into
  `data/bible.db`, is threading a user-selected translation through from
  config/UI instead of the hardcoded default — that's a product decision,
  not something this fix guessed at.
- **`bookmarks`, `vocab_list`, `versions` tables** — **documented, left
  alone, 2026-07-20**: re-confirmed via `grep -rn` for these three table
  names across `src/*.zig` (including subdirectories) and `tools/*.py` —
  zero hits in either language; nothing reads or writes them. Decision:
  leave the schema as-is (option (a) from the original note), not drop it.
  Reasoning — `bookmarks` (per-verse notes with a `note` column) and
  `vocab_list` (a personal Strong's/word list keyed by language) read as
  planned-but-unbuilt personal-study features that overlap conceptually
  with the `notes`/`lexical_favorites` tables that *did* get built, so
  they're plausible future work rather than leftover cruft — worth keeping
  around rather than a destructive `DROP TABLE` against a schema shipped
  inside a tracked, in-git production database file with no migration
  tooling in this codebase. `versions` (`slug`/`name` columns) looks like
  it was meant to be the lookup table for exactly the multi-translation
  feature `get_chapter_verses`'s `version` column above anticipates, so the
  two backlog items are likely related: if a second Bible translation is
  ever added, populating `versions` and building real UI/config around it
  is the point to revisit whether these three tables get used or removed.
  No code or migration was written for this item — it's a documentation-only
  resolution per the original scope.
- **Deuterocanonical/Ethiopian OT books likely have no BibleHub page at
  all.** Even with the language-prefix fix, scraping Tobit/Judith/Sirach/
  Enoch/Jubilees/etc. will probably still return zero interlinear rows
  (BibleHub doesn't cover them) — the scraper now exits 0 (not an error,
  correctly, since "found nothing" isn't the same as "the fetch failed"),
  but that means `llm_engine.zig` will keep re-attempting on every click
  for books that can never succeed. A future improvement: cache a
  "no source available" sentinel for these so we stop re-fetching, and say
  so in the UI instead of leaving it looking like a still-loading state.
  **Partially resolved 2026-08-25**: confirmed BibleHub *does* cover the
  Catholic/Orthodox deuterocanon (Tobit, Judith, Wisdom, Sirach, Baruch,
  1-2 Maccabees — the latter two newly added to `BIBLE_BOOKS`) via two
  sources it wasn't obvious carried them: the Apostolic Bible Polyglot
  Septuagint interlinear (`biblehub.com/interlinear/apostolic/`, Greek —
  see `tools/bible/cache_lxx_interlinear.py`) and eBible.org's full offline
  Brenton's Septuagint English translation archive (not BibleHub —
  `tools/bible/import_brenton_septuagint.py`, version `'LXXE'` in
  `versions`, resolving the "if a second translation is ever added" note
  above). Only the Ethiopian-canon-exclusive books (Enoch, Jubilees,
  Meqabyan, Tegsas, the church-order books) remain a real content gap —
  neither source covers those. `interlinear.source` ('MT'/'LXX'/'GNT', see
  `tools/bible/migrate_add_interlinear_source.py`) and `verses.version`
  now being part of the unique key is what makes two texts coexist for the
  same verse without one silently overwriting the other via `INSERT OR
  REPLACE` — that was a real, if latent, bug before this session (a second
  translation for an already-covered book would have clobbered the first).
- **`lexicon_scraper.py`'s backfill is whole-database, not chapter-scoped**,
  with a hardcoded `time.sleep(1.0)` per new Strong's number. On a large
  fresh DB this can look "stuck" rather than broken. A chapter/verse-scoped
  variant would be a more targeted (and faster) future fix.
- ~~`data/bible.db` and `data/*.wav` are intentionally gitignored~~ —
  **resolved 2026-07-19**: `data/bible.db` (31MB) and the 7 wav clips
  `data/voices.json` actually references (~7MB) are now tracked directly in
  git as explicit `.gitignore` exceptions — no git-lfs needed, well under
  GitHub's size limits. The other ~100MB of `data/` (an unreferenced 55MB
  `reference.wav`, superseded `roumie*.wav` iterations, etc.) stays
  gitignored since it was never shipped to users anyway. See
  [PACKAGING.md](PACKAGING.md).
- **Homebrew formula** (`Formula/metanoia.rb`) has a placeholder
  `sha256` — needs a real release tag cut first, then
  `shasum -a 256 <tarball>` filled in, plus a separate `homebrew-metanoia`
  tap repo created to host it.
- **Android release signing** is currently debug-signed only (sideload,
  not Play-Store-eligible) — no `signingConfigs.release` exists yet; needs
  a real keystore + CI secret when that matters.
