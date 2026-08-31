package com.bytecats.metanoia.bible

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import com.bytecats.metanoia.bible.dao.*
import com.bytecats.metanoia.models.*
import java.io.File
import java.util.zip.GZIPInputStream

/**
 * Two databases, split by volatility (see docs/MAINTENANCE.md and the
 * desktop equivalent, src/bible_db.zig's userDataDbPath()):
 *
 * - `bible.db` (contentDbFile) — verses, interlinear, lexicon. Seeded from
 *   the bundled `assets/bible.db.gz` (built from the same source data as
 *   the desktop app's data/bible.db) on first run, and re-seeded whenever
 *   CONTENT_DB_VERSION is bumped in a future release. Treat this as
 *   replaceable/disposable content, never a place to store anything the
 *   user typed.
 * - `library.db` (libraryDbFile) — bookmarks/favorites, highlights, notes,
 *   reading analytics. Created empty on first run and NEVER touched by
 *   content reseeding, so a content update can never destroy personal data.
 *
 * Both live under `context.filesDir`, which Android already keeps stable
 * across app updates (unlike the desktop .app bundle, which gets
 * wholesale-replaced) — the split still matters here because it's what
 * makes it *safe* for this class to overwrite the content DB on a content
 * version bump without needing to reason about what personal data might
 * be sitting in the same file.
 */
class BibleDatabase(private val context: Context) {
    private val contentDbFile = File(context.filesDir, "bible.db")
    private val libraryDbFile = File(context.filesDir, "library.db")

    fun openContentDb(readOnly: Boolean = false): SQLiteDatabase =
        SQLiteDatabase.openDatabase(contentDbFile.absolutePath, null, openFlags(readOnly))

    fun openLibraryDb(readOnly: Boolean = false): SQLiteDatabase =
        SQLiteDatabase.openDatabase(libraryDbFile.absolutePath, null, openFlags(readOnly))

    /** Back-compat alias — some callers still expect a single `openDb()`. */
    fun openDb(readOnly: Boolean = false): SQLiteDatabase = openContentDb(readOnly)

    val verse = VerseDao(::openContentDb)
    val favorites = FavoritesDao(::openLibraryDb)
    val highlights = HighlightsDao(::openLibraryDb)
    val notes = NotesDao(::openLibraryDb)
    val readingAnalytics = ReadingAnalyticsDao(::openLibraryDb)
    val interlinear = InterlinearDao(::openContentDb)
    val lexicon = LexiconDao(::openContentDb)

    companion object {
        fun openFlags(readOnly: Boolean): Int =
            if (readOnly) SQLiteDatabase.OPEN_READONLY
            else SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY

        /** Bump when assets/bible.db.gz changes in a way existing installs
         * need reseeded for (e.g. the Septuagint interlinear/Brenton English
         * text was added). Tracked per-install in SharedPreferences so a
         * reseed happens once per bump, not on every launch. Reseeding only
         * ever touches contentDbFile — libraryDbFile (personal data) is
         * never part of this. */
        const val CONTENT_DB_VERSION = 1

        val LIBRARY_TABLES = setOf("favorites", "highlights", "notes")
    }

    init {
        seedContentDbFromAssetsIfNeeded()
        try {
            val db = openContentDb(false)
            db.execSQL("CREATE TABLE IF NOT EXISTS lexicon (strongs TEXT PRIMARY KEY, language TEXT, lemma TEXT, transliteration TEXT, definition TEXT)")
            // `source` distinguishes which underlying text a row came from --
            // 'MT' (Masoretic Hebrew), 'LXX' (Septuagint Greek), 'GNT' (New
            // Testament Greek) -- mirrors src/bible_db.zig's interlinear
            // schema exactly so the same (book, chapter, verse, word_index)
            // can hold rows from more than one source.
            db.execSQL("CREATE TABLE IF NOT EXISTS interlinear (book TEXT, chapter INTEGER, verse INTEGER, word_index INTEGER, original_text TEXT, translation TEXT, strongs TEXT, source TEXT NOT NULL DEFAULT '', PRIMARY KEY(book, chapter, verse, word_index, source))")
            // `version` is part of the primary key (not just a column) so a
            // second English translation (Brenton's Septuagint, 'LXXE') can
            // coexist with 'NKJV' for the same verse instead of clobbering it.
            db.execSQL("CREATE TABLE IF NOT EXISTS verses (book TEXT, chapter INTEGER, verse INTEGER, text TEXT, version TEXT, PRIMARY KEY(book, chapter, verse, version))")
            db.execSQL("CREATE VIRTUAL TABLE IF NOT EXISTS verses_fts USING fts4(book, chapter, verse, text)")

            db.execSQL("""
                CREATE TRIGGER IF NOT EXISTS verses_ai AFTER INSERT ON verses BEGIN
                  INSERT INTO verses_fts(docid, book, chapter, verse, text) VALUES (new.rowid, new.book, new.chapter, new.verse, new.text);
                END;
            """.trimIndent())

            db.execSQL("""
                CREATE TRIGGER IF NOT EXISTS verses_ad AFTER DELETE ON verses BEGIN
                  INSERT INTO verses_fts(verses_fts, docid, book, chapter, verse, text) VALUES('delete', old.rowid, old.book, old.chapter, old.verse, old.text);
                END;
            """.trimIndent())

            db.execSQL("""
                CREATE TRIGGER IF NOT EXISTS verses_au AFTER UPDATE ON verses BEGIN
                  INSERT INTO verses_fts(verses_fts, docid, book, chapter, verse, text) VALUES('delete', old.rowid, old.book, old.chapter, old.verse, old.text);
                  INSERT INTO verses_fts(docid, book, chapter, verse, text) VALUES (new.rowid, new.book, new.chapter, new.verse, new.text);
                END;
            """.trimIndent())
            db.close()

            val lib = openLibraryDb(false)
            lib.execSQL("CREATE TABLE IF NOT EXISTS favorites (strongs TEXT PRIMARY KEY, lemma TEXT, definition TEXT)")
            lib.execSQL("CREATE TABLE IF NOT EXISTS highlights (book TEXT, chapter INTEGER, verse INTEGER, color INTEGER, PRIMARY KEY(book, chapter, verse))")
            lib.execSQL("CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, book TEXT, chapter INTEGER, verse INTEGER, content TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)")
            lib.execSQL("CREATE TABLE IF NOT EXISTS reading_progress (book TEXT, chapter INTEGER, first_read_at INTEGER, last_read_at INTEGER, read_count INTEGER, reading_time_seconds INTEGER DEFAULT 0, PRIMARY KEY(book, chapter))")
            lib.execSQL("CREATE TABLE IF NOT EXISTS reading_events (id INTEGER PRIMARY KEY AUTOINCREMENT, book TEXT, chapter INTEGER, timestamp INTEGER)")
            try {
                lib.execSQL("ALTER TABLE reading_progress ADD COLUMN reading_time_seconds INTEGER DEFAULT 0")
            } catch (e: Exception) {
                Log.d("BibleDatabase", "Migration for reading_time_seconds: ${e.message}")
            }
            lib.close()
        } catch (e: Exception) {
            Log.e("BibleDatabase", "Init failed: ${e.message}")
        }
    }

    /**
     * Copies the bundled `assets/bible.db.gz` over contentDbFile if it's
     * missing, or if the bundled CONTENT_DB_VERSION is newer than whatever
     * this install last seeded. Never touches libraryDbFile. Any locally
     * scraped content not covered by the new bundled asset is superseded
     * (the app can always re-scrape a gap; it can never recover a
     * personal note that got wiped, which is why that's a different file).
     */
    private fun seedContentDbFromAssetsIfNeeded() {
        val prefs = context.getSharedPreferences("metanoia_content_db", Context.MODE_PRIVATE)
        val seededVersion = prefs.getInt("seeded_version", -1)
        if (contentDbFile.exists() && seededVersion >= CONTENT_DB_VERSION) return

        val tmpFile = File(context.filesDir, "bible.db.seeding.tmp")
        try {
            context.assets.open("bible.db.gz").use { input ->
                GZIPInputStream(input).use { gz ->
                    tmpFile.outputStream().use { out -> gz.copyTo(out) }
                }
            }
            contentDbFile.delete()
            if (tmpFile.renameTo(contentDbFile)) {
                prefs.edit().putInt("seeded_version", CONTENT_DB_VERSION).apply()
                Log.i("BibleDatabase", "Seeded content DB from bundled asset (v$CONTENT_DB_VERSION)")
            }
        } catch (e: Exception) {
            // No bundled asset (e.g. a debug build without one yet) or a
            // read/write failure -- fall through and let the CREATE TABLE IF
            // NOT EXISTS statements below make an empty, still-usable DB
            // rather than crashing the app.
            Log.e("BibleDatabase", "Failed to seed content DB from assets: ${e.message}")
            tmpFile.delete()
        }
    }

    fun contentExists(): Boolean = contentDbFile.exists()
    fun exists(): Boolean = contentDbFile.exists()

    fun open(readOnly: Boolean = true): SQLiteDatabase = openContentDb(readOnly)

    fun sizeMb(): Double = (contentDbFile.length() + libraryDbFile.length()) / (1024.0 * 1024.0)

    // --- Delegated passthroughs (backward-compatible) ---

    fun getTableRows(tableName: String, limit: Int = 100): List<Map<String, String>> =
        if (tableName in LIBRARY_TABLES) LibraryVerseDao(::openLibraryDb).getTableRows(tableName, limit)
        else verse.getTableRows(tableName, limit)

    fun getChapter(book: String, chapter: Int, preferredVersion: String? = null): List<Verse> = verse.getChapter(book, chapter, preferredVersion)
    fun insertVerses(book: String, chapter: Int, verses: List<Verse>, version: String) = verse.insertVerses(book, chapter, verses, version)
    fun searchVerses(query: String): List<SearchResult> = verse.searchVerses(query)
    fun getStats(): LibraryStats {
        val contentStats = verse.getStats()
        val libDb = openLibraryDb()
        val n = libDb.rawQuery("SELECT COUNT(*) FROM notes", null).use { if (it.moveToFirst()) it.getInt(0) else 0 }
        val h = libDb.rawQuery("SELECT COUNT(*) FROM highlights", null).use { if (it.moveToFirst()) it.getInt(0) else 0 }
        libDb.close()
        return contentStats.copy(notesCount = n, highlightsCount = h, dbSizeMb = sizeMb())
    }
    fun clearTable(tableName: String) {
        if (tableName in LIBRARY_TABLES) {
            val db = openLibraryDb(); db.execSQL("DELETE FROM $tableName"); db.execSQL("VACUUM"); db.close()
        } else {
            verse.clearTable(tableName)
        }
    }
    fun factoryReset() {
        verse.clearContentTables()
        val lib = openLibraryDb()
        lib.execSQL("DELETE FROM highlights"); lib.execSQL("DELETE FROM notes"); lib.execSQL("DELETE FROM favorites")
        lib.execSQL("VACUUM"); lib.close()
    }
    fun checkIntegrity(): String = verse.checkIntegrity()
    fun vacuum() {
        verse.vacuum()
        val db = openLibraryDb(); db.execSQL("VACUUM"); db.close()
    }
    fun getBookCompletion(): Map<String, Float> = verse.getBookCompletion()
    fun getChapterWordCounts(book: String): Map<Int, Int> = verse.getChapterWordCounts(book)
    fun getDownloadedChapters(book: String): Set<Int> = verse.getDownloadedChapters(book)
    fun recordReadingTime(book: String, chapter: Int, additionalSeconds: Long) = readingAnalytics.recordReadingTime(book, chapter, additionalSeconds)
    fun getChapterReadingTimes(book: String): Map<Int, Long> = readingAnalytics.getChapterReadingTimes(book)

    fun saveFavorite(strongs: String, lemma: String, definition: String) = favorites.saveFavorite(strongs, lemma, definition)
    fun getFavorites(): List<Favorite> = favorites.getFavorites()
    fun deleteFavorite(strongs: String) = favorites.deleteFavorite(strongs)

    fun setHighlight(book: String, chapter: Int, verse: Int, color: Int) = highlights.setHighlight(book, chapter, verse, color)
    fun getHighlights(book: String, chapter: Int): Map<Int, Int> = highlights.getHighlights(book, chapter)

    fun saveNote(book: String, chapter: Int, verse: Int, content: String) = notes.saveNote(book, chapter, verse, content)
    fun getNotes(book: String, chapter: Int, verse: Int): List<Note> = notes.getNotes(book, chapter, verse)

    fun recordChapterRead(book: String, chapter: Int) = readingAnalytics.recordChapterRead(book, chapter)
    fun getReadCompletion(): Map<String, Float> = readingAnalytics.getReadCompletion()
    fun getMostReadBooks(limit: Int = 5): List<Pair<String, Int>> = readingAnalytics.getMostReadBooks(limit)
    fun getHotChapters(limit: Int = 10): List<HotChapter> = readingAnalytics.getHotChapters(limit)
    fun getReadingEventCounts(sinceMillis: Long): Int = readingAnalytics.getReadingEventCounts(sinceMillis)
    fun getFirstEverReadTimestamp(): Long? = readingAnalytics.getFirstEverReadTimestamp()
    fun getReadEpochDaysDescending(): List<Long> = readingAnalytics.getReadEpochDaysDescending()
    fun getDailyReadCounts(days: Int): List<Pair<Long, Int>> = readingAnalytics.getDailyReadCounts(days)
    fun getDayOfWeekCounts(): IntArray = readingAnalytics.getDayOfWeekCounts()
    fun getHourOfDayCounts(): IntArray = readingAnalytics.getHourOfDayCounts()
    fun getTestamentReadCounts(): Map<String, Int> = readingAnalytics.getTestamentReadCounts()
    fun clearReadingHistory() = readingAnalytics.clearReadingHistory()

    fun getInterlinear(book: String, chapter: Int, verse: Int, preferredSource: String? = null): List<InterlinearWord> = interlinear.getInterlinear(book, chapter, verse, preferredSource)
    fun insertInterlinearWords(book: String, chapter: Int, words: List<InterlinearWordWithVerse>, source: String) = interlinear.insertInterlinearWords(book, chapter, words, source)

    fun getLexiconDetail(strongs: String): LexiconEntry = lexicon.getLexiconDetail(strongs)
    fun insertLexicon(strongs: String, language: String, lemma: String, transliteration: String, definition: String) = lexicon.insertLexicon(strongs, language, lemma, transliteration, definition)
}

/** Thin `getTableRows`-only helper so BibleDatabase.getTableRows() can
 * inspect a library table without VerseDao (which is wired to the content
 * DB) needing to know about library tables at all. */
private class LibraryVerseDao(private val openDb: () -> SQLiteDatabase) {
    fun getTableRows(tableName: String, limit: Int): List<Map<String, String>> {
        require(tableName in BibleDatabase.LIBRARY_TABLES) { "Invalid table name: $tableName" }
        val list = mutableListOf<Map<String, String>>()
        val db = openDb()
        try {
            val cursor = db.rawQuery("SELECT * FROM $tableName LIMIT $limit", null)
            val columns = cursor.columnNames
            while (cursor.moveToNext()) {
                val row = mutableMapOf<String, String>()
                columns.forEachIndexed { i, name -> row[name] = cursor.getString(i) ?: "NULL" }
                list.add(row)
            }
            cursor.close()
        } catch (e: Exception) {
            Log.e("BibleDatabase", "Inspect fail: ${e.message}")
        } finally { db.close() }
        return list
    }
}
