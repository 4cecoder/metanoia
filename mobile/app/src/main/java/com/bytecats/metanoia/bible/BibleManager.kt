package com.bytecats.metanoia.bible

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.io.IOException
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import com.bytecats.metanoia.models.*
import com.bytecats.metanoia.models.BOOKS
import com.bytecats.metanoia.gateway.GatewayClient
import com.bytecats.metanoia.settings.SettingsManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Live-scraping + book metadata. Storage itself (both the content DB and
 * the personal-data library DB) lives in [BibleDatabase] -- this class used
 * to hand-roll its own duplicate SQLiteDatabase/CREATE TABLE/raw-query
 * layer against the same underlying file, which is exactly the kind of
 * "two systems touching the same data differently" drift that made the
 * Android storage layer hard to reason about. Everything storage-related
 * below just delegates to [database].
 */
class BibleManager(private val context: Context) {
    private val client = OkHttpClient()
    private val database = BibleDatabase(context)
    private val settings = SettingsManager(context)

    private val scraperManager = ScraperManager(
        scrapers = listOf(
            BibleGatewayScraper(client = client),
            BibleHubTextScraper(client = client)
        ),
        cache = ScratchpadCache(context)
    )

    private val hebrewLexiconRepository = com.bytecats.metanoia.bible.lexicon.HebrewLexiconRepository(client) { database.openContentDb(false) }

    val books = BOOKS
    @Suppress("DEPRECATION") // Deprecated gateway used for backward compatibility
    val gateway = GatewayClient(baseUrlProvider = { "http://192.168.122.2:8000" })

    // --- Old Testament text tradition (Septuagint by default, Masoretic if
    // the user opted in under Settings -- see SettingsManager.otTextTradition
    // and the desktop equivalent, src/main.zig's load_chapter_into_study) ---

    private fun useMasoretic() = settings.otTextTradition == "masoretic"

    /** 'LXXE' for an Old Testament book when reading Septuagint (default),
     * else 'NKJV'. The New Testament and Ethiopian-canon-only books only
     * ever have NKJV verse text cached, so they always resolve to 'NKJV'. */
    private fun preferredVerseVersion(book: String): String {
        val testament = books.find { it.name == book }?.testament
        return if (testament == "Old" && !useMasoretic()) "LXXE" else "NKJV"
    }

    /** 'LXX'/'MT' for an Old Testament book depending on the tradition
     * setting, else 'GNT' for the New Testament / Ethiopian-canon books. */
    private fun preferredInterlinearSource(book: String): String {
        val testament = books.find { it.name == book }?.testament
        if (testament != "Old") return "GNT"
        return if (useMasoretic()) "MT" else "LXX"
    }

    // --- Table inspector / stats / maintenance -- delegate to BibleDatabase ---

    fun getTableRows(tableName: String, limit: Int = 100): List<Map<String, String>> =
        database.getTableRows(tableName, limit)

    fun getStats(): LibraryStats = database.getStats()
    fun clearTable(tableName: String) = database.clearTable(tableName)
    fun factoryReset() = database.factoryReset()
    fun checkIntegrity(): String = database.checkIntegrity()
    fun vacuumDatabase() = database.vacuum()

    // --- Favorites / highlights / notes -- personal data, library DB ---

    fun saveFavorite(strongs: String, lemma: String, definition: String) = database.saveFavorite(strongs, lemma, definition)
    fun getFavorites(): List<Favorite> = database.getFavorites()
    fun deleteFavorite(strongs: String) = database.deleteFavorite(strongs)

    fun setHighlight(book: String, chapter: Int, verse: Int, color: Int) = database.setHighlight(book, chapter, verse, color)
    fun getHighlights(book: String, chapter: Int): Map<Int, Int> = database.getHighlights(book, chapter)

    fun saveNote(book: String, chapter: Int, verse: Int, content: String) = database.saveNote(book, chapter, verse, content)
    fun getNotes(book: String, chapter: Int, verse: Int): List<Note> = database.getNotes(book, chapter, verse)

    // --- Verses / interlinear / lexicon -- content DB, tradition-aware ---

    fun searchVerses(query: String): List<SearchResult> = database.searchVerses(query)

    fun getBookCompletion(): Map<String, Float> = database.getBookCompletion()

    fun getChapter(book: String, chapter: Int): List<Pair<Int, String>> =
        database.getChapter(book, chapter, preferredVerseVersion(book)).map { it.number to it.text }

    fun getInterlinear(book: String, chapter: Int, verse: Int): List<InterlinearWord> =
        database.getInterlinear(book, chapter, verse, preferredInterlinearSource(book))

    fun getLexiconDetail(strongs: String): Pair<String, String> {
        val db = database.openContentDb()
        var cursor = db.rawQuery("SELECT lemma, definition FROM lexicon WHERE strongs = ?", arrayOf(strongs))
        if (cursor.moveToFirst()) {
            val res = Pair(cursor.getString(0) ?: "", cursor.getString(1) ?: "")
            cursor.close()
            db.close()
            return res
        }
        cursor.close()

        val num = strongs.filter { it.isDigit() }
        val alt = if (strongs.all { it.isDigit() }) "H$num" else num
        cursor = db.rawQuery("SELECT lemma, definition FROM lexicon WHERE strongs = ?", arrayOf(alt))
        var res = Pair("", "")
        if (cursor.moveToFirst()) res = Pair(cursor.getString(0) ?: "", cursor.getString(1) ?: "")
        cursor.close()
        db.close()
        return res
    }

    // --- Live scraping: gap-filling on top of the bundled content DB ---
    // (see BibleDatabase.CONTENT_DB_VERSION / seedContentDbFromAssetsIfNeeded)

    suspend fun fetchChapter(book: String, chapter: Int, version: String = "NKJV") = withContext(Dispatchers.IO) {
        if (book in DeuterocanonRouting.NO_SOURCE_BOOKS) {
            throw IOException(DeuterocanonRouting.noSourceMessage(book))
        }
        val db = database.openContentDb(false); db.beginTransaction()
        try {
            if (book in WikisourceApocryphaScraper.SUPPORTED_BOOKS) {
                val scraper = WikisourceApocryphaScraper(client = client)
                scraper.scrapeChapter(book, chapter) { verseNum, text ->
                    db.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
                        arrayOf(book, chapter, verseNum, text, "KJV-Apocrypha"))
                }
            } else {
                // Use ScraperManager for rate limiting and fallback
                scraperManager.fetchChapter(book, chapter, version) { verseNum, text ->
                    db.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
                        arrayOf(book, chapter, verseNum, text, version))
                }
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); db.close() }
    }

    suspend fun fetchInterlinear(book: String, chapter: Int) = withContext(Dispatchers.IO) {
        if (book in DeuterocanonRouting.NO_SOURCE_BOOKS || book in WikisourceApocryphaScraper.SUPPORTED_BOOKS) {
            return@withContext
        }
        // This scraper only ever hits BibleHub's standard (non-Septuagint)
        // interlinear template, same as src/native_scraper.zig's
        // scrapeInterlinear -- so the source tag is fully determined by
        // testament: Old -> Masoretic Hebrew, else -> Greek New Testament.
        // There is no on-device Septuagint (LXX) scraping today; LXX
        // content only arrives via the bundled content DB.
        val testament = books.find { it.name == book }?.testament
        val source = if (testament == "Old") "MT" else "GNT"
        val db = database.openContentDb(false); db.beginTransaction()
        try {
            val scraper = BibleScraper(client = client)
            scraper.scrapeInterlinear(book, chapter) { verse, wordIdx, original, translation, strongs ->
                db.execSQL("INSERT OR REPLACE INTO interlinear (book, chapter, verse, word_index, original_text, translation, strongs, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    arrayOf(book, chapter, verse, wordIdx, original, translation, strongs, source))
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); db.close() }
    }

    suspend fun scrapeChapter(book: String, chapter: Int, version: String = "NKJV") = withContext(Dispatchers.IO) {
        try {
            fetchChapter(book, chapter, version)
        } catch (e: Exception) {
            Log.e("BibleManager", "scrapeChapter failed for $book $chapter: ${e.message}", e)
            throw e
        }
    }

    suspend fun scrapeInterlinear(book: String, chapter: Int) = withContext(Dispatchers.IO) {
        try {
            fetchInterlinear(book, chapter)
        } catch (e: Exception) {
            Log.e("BibleManager", "scrapeInterlinear failed for $book $chapter: ${e.message}", e)
            throw e
        }
    }

    suspend fun scrapeStrong(strongs: String, bookName: String? = null) = withContext(Dispatchers.IO) {
        val isG = if (bookName != null) books.find { it.name == bookName }?.testament == "New" else strongs.startsWith("G")
        if (isG) scrapeGreekStrong(strongs) else hebrewLexiconRepository.scrapeHebrewStrong(strongs)
    }

    private fun scrapeGreekStrong(strongs: String) {
        val num = strongs.filter { it.isDigit() }
        val request = Request.Builder().url("https://biblehub.com/greek/$num.htm").header("User-Agent", "Mozilla/5.0").build()
        try {
            val response = client.newCall(request).execute()
            val doc = Jsoup.parse(response.body?.string() ?: return)
            val lemma = doc.select("span.greek").first()?.text()?.trim() ?: ""
            val tr = doc.select("span.translit").first()?.text()?.trim() ?: ""
            var def = doc.select("div.strongsnt").text().trim()
            if (def.isEmpty()) { val lb = doc.select("div#leftbox").first(); lb?.select("iframe, script, ins, .vheading")?.remove(); def = lb?.text()?.trim()?.take(3000) ?: "" }
            if (def.isNotEmpty()) { val db = database.openContentDb(false); db.execSQL("INSERT OR REPLACE INTO lexicon (strongs, language, lemma, transliteration, definition) VALUES (?, 'greek', ?, ?, ?)", arrayOf(strongs, lemma, tr, def)); db.close() }
        } catch (e: Exception) { Log.e("BibleManager", "Failed to scrape Greek strongs: $strongs", e) }
    }

    // --- DELEGATED METHODS TO BibleDatabase (for ReadingAnalyticsScreen) ---
    fun getMostReadBooks(limit: Int = 5): List<Pair<String, Int>> = database.getMostReadBooks(limit)
    fun getHotChapters(limit: Int = 10): List<HotChapter> = database.getHotChapters(limit)
    fun getReadingEventCounts(sinceMillis: Long): Int = database.getReadingEventCounts(sinceMillis)
    fun getFirstEverReadTimestamp(): Long? = database.getFirstEverReadTimestamp()
    fun getReadCompletion(): Map<String, Float> = database.getReadCompletion()
    fun clearReadingHistory() = database.clearReadingHistory()
    fun getReadEpochDaysDescending(): List<Long> = database.getReadEpochDaysDescending()
    fun getDailyReadCounts(days: Int): List<Pair<Long, Int>> = database.getDailyReadCounts(days)
    fun getDayOfWeekCounts(): IntArray = database.getDayOfWeekCounts()
    fun getHourOfDayCounts(): IntArray = database.getHourOfDayCounts()
    fun getTestamentReadCounts(): Map<String, Int> = database.getTestamentReadCounts()
    fun recordReadingTime(book: String, chapter: Int, additionalSeconds: Long) = database.recordReadingTime(book, chapter, additionalSeconds)
    fun getChapterReadingTimes(book: String): Map<Int, Long> = database.getChapterReadingTimes(book)
    fun getChapterWordCounts(book: String): Map<Int, Int> = database.getChapterWordCounts(book)
    fun getDownloadedChapters(book: String): Set<Int> = database.getDownloadedChapters(book)

    /**
     * Calculates detailed reading progress for a book using time-based metrics.
     * Considers both chapter visits and actual reading time vs word count.
     */
    fun getBookReadingProgress(book: String): ReadingStats.BookReadingProgress {
        val chapterWordCounts = getChapterWordCounts(book)
        val chapterReadingTimes = getChapterReadingTimes(book)
        val totalChapters = books.find { it.name == book }?.chapters ?: chapterWordCounts.size

        return ReadingStats.BookReadingProgress(
            bookName = book,
            totalChapters = totalChapters,
            completionFraction = ReadingStats.calculateBookCompletion(
                chapterReadingTimes = chapterReadingTimes,
                chapterWordCounts = chapterWordCounts,
                totalChapters = totalChapters
            ),
            chapterStatus = ReadingStats.getChapterReadingStatus(
                chapterReadingTimes = chapterReadingTimes,
                chapterWordCounts = chapterWordCounts
            ),
            totalWords = ReadingStats.calculateBookWordCount(chapterWordCounts),
            totalReadingTimeSeconds = chapterReadingTimes.values.sum()
        )
    }

    /**
     * Gets overall reading completion across all books using time-based metrics.
     */
    fun getTimeBasedCompletion(): Map<String, Float> {
        return books.associate { book ->
            val progress = getBookReadingProgress(book.name)
            book.name to progress.completionFraction
        }
    }

    /**
     * Estimates current reading session progress and completion time.
     */
    fun estimateCurrentReadingProgress(book: String, chapter: Int): Pair<Float, Long> {
        val wordCount = getChapterWordCounts(book)[chapter] ?: 0
        val readingTime = getChapterReadingTimes(book)[chapter] ?: 0L

        return ReadingStats.estimateSessionCompletion(
            wordCount = wordCount,
            elapsedTimeSeconds = readingTime
        )
    }

}
