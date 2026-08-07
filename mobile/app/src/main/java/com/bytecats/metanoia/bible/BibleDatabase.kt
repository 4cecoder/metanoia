package com.bytecats.metanoia.bible

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import com.bytecats.metanoia.bible.dao.*
import com.bytecats.metanoia.models.*
import java.io.File

/**
 * Bible database manager providing access to all Bible-related DAOs.
 *
 * Manages the SQLite database file and provides typed access to different data access objects:
 * - [VerseDao]: Bible verse queries and storage
 * - [FavoritesDao]: User's favorite Strong's numbers
 * - [HighlightsDao]: Verse highlights with colors
 * - [NotesDao]: User notes on passages
 * - [ReadingAnalyticsDao]: Reading progress tracking
 * - [InterlinearDao]: Interlinear word-by-word translations
 * - [LexiconDao]: Strong's lexicon definitions
 *
 * Database location: /data/data/com.bytecats.metanoia/files/bible.db
 *
 * @property context Android context for file system access
 */
class BibleDatabase(private val context: Context) {
    private val dbFile = File(context.filesDir, "bible.db")

    /**
     * Open the Bible database with specified access mode.
     *
     * @param readOnly If true, opens in read-only mode; otherwise opens in read-write mode
     * @return SQLiteDatabase instance
     */
    fun openDb(readOnly: Boolean = false): SQLiteDatabase =
        SQLiteDatabase.openDatabase(dbFile.absolutePath, null, openFlags(readOnly))
    val verse = VerseDao(::openDb)
    val favorites = FavoritesDao(::openDb)
    val highlights = HighlightsDao(::openDb)
    val notes = NotesDao(::openDb)
    val readingAnalytics = ReadingAnalyticsDao(::openDb)
    val interlinear = InterlinearDao(::openDb)
    val lexicon = LexiconDao(::openDb)

    companion object {
        fun openFlags(readOnly: Boolean): Int =
            if (readOnly) SQLiteDatabase.OPEN_READONLY
            else SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY
    }

    init {
        try {
            val db = openDb(false)
            db.execSQL("CREATE TABLE IF NOT EXISTS favorites (strongs TEXT PRIMARY KEY, lemma TEXT, definition TEXT)")
            db.execSQL("CREATE TABLE IF NOT EXISTS lexicon (strongs TEXT PRIMARY KEY, language TEXT, lemma TEXT, transliteration TEXT, definition TEXT)")
            db.execSQL("CREATE TABLE IF NOT EXISTS interlinear (book TEXT, chapter INTEGER, verse INTEGER, word_index INTEGER, original_text TEXT, translation TEXT, strongs TEXT, PRIMARY KEY(book, chapter, verse, word_index))")
            db.execSQL("CREATE TABLE IF NOT EXISTS highlights (book TEXT, chapter INTEGER, verse INTEGER, color INTEGER, PRIMARY KEY(book, chapter, verse))")
            db.execSQL("CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, book TEXT, chapter INTEGER, verse INTEGER, content TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)")
            db.execSQL("CREATE TABLE IF NOT EXISTS verses (book TEXT, chapter INTEGER, verse INTEGER, text TEXT, version TEXT, PRIMARY KEY(book, chapter, verse))")
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
            db.execSQL("CREATE TABLE IF NOT EXISTS reading_progress (book TEXT, chapter INTEGER, first_read_at INTEGER, last_read_at INTEGER, read_count INTEGER, reading_time_seconds INTEGER DEFAULT 0, PRIMARY KEY(book, chapter))")
            db.execSQL("CREATE TABLE IF NOT EXISTS reading_events (id INTEGER PRIMARY KEY AUTOINCREMENT, book TEXT, chapter INTEGER, timestamp INTEGER)")
            
            // Migration: Add reading_time_seconds column if it doesn't exist
            try {
                db.execSQL("ALTER TABLE reading_progress ADD COLUMN reading_time_seconds INTEGER DEFAULT 0")
            } catch (e: Exception) {
                // Column already exists or other error - ignore
                Log.d("BibleDatabase", "Migration for reading_time_seconds: ${e.message}")
            }
            
            db.close()
        } catch (e: Exception) {
            Log.e("BibleDatabase", "Init failed: ${e.message}")
        }
    }

    fun exists(): Boolean = dbFile.exists()

    fun open(readOnly: Boolean = true): SQLiteDatabase = openDb(readOnly)

    fun sizeMb(): Double = dbFile.length() / (1024.0 * 1024.0)

    // --- Delegated passthroughs (backward-compatible) ---

    fun getTableRows(tableName: String, limit: Int = 100): List<Map<String, String>> =
        verse.getTableRows(tableName, limit)

    fun getChapter(book: String, chapter: Int): List<Verse> = verse.getChapter(book, chapter)
    fun insertVerses(book: String, chapter: Int, verses: List<Verse>, version: String) = verse.insertVerses(book, chapter, verses, version)
    fun searchVerses(query: String): List<SearchResult> = verse.searchVerses(query)
    fun getStats(): LibraryStats {
        val stats = verse.getStats()
        return LibraryStats(stats.versesOt, stats.versesNt, stats.lexiconHeb, stats.lexiconGk, stats.notesCount, stats.highlightsCount, stats.interlinearCount, sizeMb())
    }
    fun clearTable(tableName: String) = verse.clearTable(tableName)
    fun factoryReset() = verse.factoryReset()
    fun checkIntegrity(): String = verse.checkIntegrity()
    fun vacuum() = verse.vacuum()
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

    fun getInterlinear(book: String, chapter: Int, verse: Int): List<InterlinearWord> = interlinear.getInterlinear(book, chapter, verse)
    fun insertInterlinearWords(book: String, chapter: Int, words: List<InterlinearWordWithVerse>) = interlinear.insertInterlinearWords(book, chapter, words)

    fun getLexiconDetail(strongs: String): LexiconEntry = lexicon.getLexiconDetail(strongs)
    fun insertLexicon(strongs: String, language: String, lemma: String, transliteration: String, definition: String) = lexicon.insertLexicon(strongs, language, lemma, transliteration, definition)
}
