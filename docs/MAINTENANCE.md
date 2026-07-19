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
scraped from BibleHub by two Python scripts (`tools/interlinear_scraper.py`,
`tools/lexicon_scraper.py`) run as subprocesses from
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

## Quick-wins backlog (noticed, not fixed — scoped out to avoid creep)

- **`get_chapter_verses` ignores the `version` column.** The `verses` table
  has a unique index on `(book, chapter, verse, version)` implying multiple
  translations were intended, but the query
  (`bible_db.zig:get_chapter_verses`) has no `WHERE version=...` — if more
  than one translation is ever loaded, results could mix/duplicate. Not
  fixed because the intended default-version behavior isn't specified
  anywhere; needs a product decision, not a guess.
- **`bookmarks`, `vocab_list`, `versions` tables** exist in the shipped
  `data/bible.db` schema but are read/written by no Zig or Python code
  found this session. Either dead schema from an earlier design or
  planned-but-unbuilt features — worth a decision either way rather than
  silently carrying unused tables indefinitely.
- **Deuterocanonical/Ethiopian OT books likely have no BibleHub page at
  all.** Even with the language-prefix fix, scraping Tobit/Judith/Sirach/
  Enoch/Jubilees/etc. will probably still return zero interlinear rows
  (BibleHub doesn't cover them) — the scraper now exits 0 (not an error,
  correctly, since "found nothing" isn't the same as "the fetch failed"),
  but that means `llm_engine.zig` will keep re-attempting on every click
  for books that can never succeed. A future improvement: cache a
  "no source available" sentinel for these so we stop re-fetching, and say
  so in the UI instead of leaving it looking like a still-loading state.
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
