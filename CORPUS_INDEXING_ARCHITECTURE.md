## Metanoia Bible Reader - Component Architecture

### Component: Biblical Corpus Indexing

**Purpose:** Index ALL books across ALL canons. Prevent hiding. Make everything discoverable.

**Location:** `bible/UniversalBibleSearch.kt`

**Responsibilities:**
- Search ALL books without canonical filtering
- Get books by textual tradition (Masoretic, Septuagint, New Testament, Ethiopic)
- Get Septuagint-only books (deuterocanonical)
- Get Ethiopic-only books
- Get universal books (in all canons)
- Get books missing from Protestant canon
- Get corpus statistics

**Key Functions:**
```kotlin
fun searchBooks(query: String): List<BibleBook>
fun getAllBooksByTradition(): Map<TextTradition, List<BibleBook>>
fun getSeptuagintOnlyBooks(): List<BibleBook>
fun getEthiopicOnlyBooks(): List<BibleBook>
fun getUniversalBooks(): List<BibleBook>
fun getMissingFromProtestant(): List<BibleBook>
fun getCorpusStatistics(): CorpusStatistics
```

**Design Principles:**
1. **No Hiding:** Search returns ALL matching books, no canonical filtering
2. **Reveal the Past:** Explicitly surface books Protestantism removed
3. **Tradition-First:** Organize by textual tradition (Hebrew → Greek → Ge'ez)
4. **Statistical Transparency:** Show exactly what's in each tradition

---

### Component: Universal Search UI

**Purpose:** Compose components for displaying search results with full metadata.

**Location:** `ui/components/search/UniversalSearchComponents.kt`

**Responsibilities:**
- Search bar with universal search
- Book cards showing tradition and canon badges
- Tradition badges (color-coded)
- Canon badges (color-coded)
- Search results list
- Corpus statistics card
- Empty states

**Key Components:**
```kotlin
@Composable fun UniversalSearchBar(query, onQueryChange)
@Composable fun BookCard(book, onClick)
@Composable fun TraditionBadge(tradition)
@Composable fun CanonBadges(canons)
@Composable fun SearchResultsList(books, onBookClick)
@Composable fun CorpusStatisticsCard(stats)
```

**Design Principles:**
1. **Full Metadata:** Show tradition, canon, section for every book
2. **Visual Clarity:** Color-coded badges for traditions
3. **No Filter Indicators:** Don't hide books with UI tricks
4. **Statistical Honesty:** Show counts, not "..." ellipses

---

### Component: Corpus Explorer Screen

**Purpose:** Screen for exploring the COMPLETE biblical corpus by tradition.

**Location:** `ui/screens/CorpusExplorerScreen.kt`

**Responsibilities:**
- Show all books organized by textual tradition
- Tab navigation (Corpus, Septuagint, Ethiopic, Missing, Search)
- Statistics overview
- Tradition sections with descriptions
- "Books Missing from Protestant Canon" section
- Universal search (no canonical filtering)

**Key Functions:**
```kotlin
@Composable fun CorpusExplorerScreen(bibleManager, onBookClick, onBackClick)
@Composable fun CorpusOverviewContent(corpusStats, allBooksByTradition, onBookClick)
@Composable fun TraditionSection(tradition, books, onBookClick, description)
@Composable fun MissingBooksSection(missingBooks, onBookClick)
```

**Design Principles:**
1. **Tradition-First Navigation:** Tabs for Masoretic, Septuagint, Ethiopic
2. **Reveal the Missing:** Explicit "Missing from Protestant" section
3. **Explain the History:** Context for WHY books are missing
4. **No Canonical Filtering:** Search across ALL canons

---

### Component: Textual Tradition Tracking

**Purpose:** Track which textual tradition each book belongs to.

**Location:** `models/BibleBook.kt`

**Enums:**
```kotlin
enum class TextTradition {
    Masoretic,    // Hebrew/Aramaic, 39 books
    Septuagint,   // Greek, includes deuterocanonical books
    NewTestament, // Greek, 27 books
    Ethiopic      // Ge'ez, Ethiopian-canon-only books
}
```

**Responsibilities:**
- Distinguish Masoretic from Septuagint
- Track Ethiopic texts
- Provide `isSeptuagint` computed property
- Support tradition-based filtering

---

### Component: Canon Membership

**Purpose:** Track which canons include each book.

**Location:** `models/BibleBook.kt`

**Enums:**
```kotlin
enum class Canon {
    Protestant,
    Catholic,
    Orthodox,
    Ethiopian
}
```

**Responsibilities:**
- Track canon membership per book
- Support multi-canon books
- Provide `isDeuterocanonical` and `isEthiopianExclusive` computed properties
- Generate human-readable canonical status

---

### Component: Sectional Grouping

**Purpose:** Logical grouping of books within a testament.

**Location:** `models/BibleBook.kt`

**Enums:**
```kotlin
enum class BookSection {
    Pentateuch, Historical, Wisdom, MajorProphets, MinorProphets,
    Deuterocanonical, EthiopianCanon,
    Gospels, Acts, PaulineEpistles, GeneralEpistles, Apocalyptic
}
```

**Responsibilities:**
- Group books logically
- Support section-based navigation
- Preserve canonical order within sections

---

### Component: Error Handling & Routing

**Purpose:** Route books to correct scrapers and handle errors gracefully.

**Location:** `bible/BibleManager.kt`

**Key Functions:**
```kotlin
suspend fun fetchChapter(book, chapter, version)
suspend fun fetchInterlinear(book, chapter)
suspend fun scrapeChapter(book, chapter, version)
suspend fun scrapeInterlinear(book, chapter)
```

**Responsibilities:**
- Route to Wikisource for deuterocanonical books
- Route to Enoch scraper for Ethiopian books
- Route to BibleGateway for standard books
- Throw clear errors for NO_SOURCE books
- Log errors instead of crashing

---

### Component: Cache Management

**Purpose:** Cache-first fetching to protect endpoints from rate limiting.

**Location:** `bible/BibleCacheManager.kt`

**Key Functions:**
```kotlin
suspend fun ensureChapter(book, chapter): Boolean
suspend fun prefetchBook(book)
suspend fun prefetchWholeBible()
fun isBookCached(book): Boolean
fun cachedChapterCount(book): Int
```

**Responsibilities:**
- Check cache before fetching
- Don't refetch cached content
- Prefetch entire books/books
- Track progress and errors
- Respect user canonical preferences

---

### Component: Settings Integration

**Purpose:** User preferences for canonical display.

**Location:** `settings/SettingsManager.kt` (existing)

**Settings:**
- `showApocrypha`: Include Catholic/Orthodox deuterocanonical books
- `showEthiopian`: Include Ethiopian-canon-only books
- `bibleGatewayVersion`: Translation version

**Responsibilities:**
- Store user canonical preferences
- Map preferences to canon presets
- Persist across sessions

---

## Component Dependencies

```
CorpusExplorerScreen
    ├─ UniversalBibleSearch
    │   └─ BibleBook (models)
    │       ├─ Canon enum
    │       ├─ TextTradition enum
    │       └─ BookSection enum
    ├─ UniversalSearchComponents (UI)
    │   └─ BibleBook (models)
    └─ BibleManager (for searchVersesEverywhere)

UniversalSearchComponents
    └─ BibleBook (models)

BibleManager
    ├─ WikisourceApocryphaScraper
    ├─ WikisourceEnochScraper
    └─ BibleScraper

BibleCacheManager
    ├─ BibleManager
    └─ SettingsManager
```

---

## Anti-Patterns Avoided

### 1. Hiding by Default
❌ **Avoid:** Defaulting to Protestant canon and hiding everything else
✅ **Do:** Show ALL books by default in corpus explorer, filter only by explicit user choice

### 2. Canonical Filtering in Search
❌ **Avoid:** Search that only returns books in user's selected canon
✅ **Do:** Universal search returns ALL matching books across ALL canons

### 3. Metadata Concealment
❌ **Avoid:** Showing only book name and chapter count
✅ **Do:** Show tradition, canon, section, and canonical status for EVERY book

### 4. "Protestant First" Ordering
❌ **Avoid:** Ordering books by Protestant canonical order
✅ **Do:** Order by textual tradition (Hebrew → Greek → Ge'ez) or section

### 5. Apocrypha as "Optional"
❌ **Avoid:** Labeling deuterocanonical books as "optional" or "extra"
✅ **Do:** Treat all books equally, show which canons include them

### 6. No History Context
❌ **Avoid:** Presenting the 66-book canon as "the Bible"
✅ **Do:** Explain historical context, show which books were removed and why

---

## Test Coverage

### Universal Bible Search Tests
- `UniversalBibleSearchTest.kt` (12 tests)
  - Search finds all matching books
  - Case-insensitive search
  - Tradition-based search
  - Books by tradition
  - Septuagint-only books
  - Ethiopic-only books
  - Universal books
  - Missing from Protestant
  - Canon-exclusive books
  - Corpus statistics
  - Nothing is hidden
  - Can search by section

### Canon-Aware Book Tests
- `CanonAwareBibleBookTest.kt` (20 tests)
  - Protestant canon = 66 books
  - Catholic canon > 66 books
  - Ethiopian canon is broadest
  - Canon membership correctness
  - Tradition assignments
  - Sectional grouping
  - Canonical ordering
  - Canonical status descriptions
  - Strong's prefix correctness

### Caching Behavior Tests
- `BibleCachingBehaviorTest.kt` (12 tests)
  - Cache-first behavior
  - No refetch when cached
  - Prefetch is idempotent
  - Error recovery
  - Prefetch continues after failure
  - Cache fraction accuracy

### Wisdom Scraper Tests
- `BookOfWisdomScraperRoutingTest.kt` (6 tests)
  - Wisdom routing to Wikisource
  - Wisdom in SUPPORTED_BOOKS
  - Wisdom NOT in NO_SOURCE_BOOKS
  - Verse parsing
  - Network error propagation

---

## Future Enhancements

### 1. Verse-Level Indexing
- Index verses by tradition
- Show multiple translations (KJV, Septuagint, Ge'ez)
- Cross-tradition verse comparison

### 2. Canonical Timeline
- Show when books were added/removed
- Timeline of canon development
- Interactive canon evolution visualization

### 3. Reading Plans by Tradition
- Masoretic reading plan
- Septuagint reading plan
- Ethiopic reading plan

### 4. Annotations by Tradition
- Track which tradition a note applies to
- Show tradition-specific commentary

### 5. Export by Tradition
- Export Masoretic OT only
- Export complete Ethiopian canon
- Export "missing from Protestant" books