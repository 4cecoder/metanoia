package com.bytecats.metanoia.bible

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.io.IOException
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import java.io.File
import com.bytecats.metanoia.models.*
import com.bytecats.metanoia.models.BOOKS
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class BibleManager(private val context: Context) {
    private val dbFile = File(context.filesDir, "bible.db")
    private val client = OkHttpClient()

    private fun getDb(readOnly: Boolean = true): SQLiteDatabase {
        return SQLiteDatabase.openDatabase(dbFile.absolutePath, null, if (readOnly) SQLiteDatabase.OPEN_READONLY else SQLiteDatabase.OPEN_READWRITE)
    }

    init {
        try {
            val db = getDb(false)
            db.execSQL("CREATE TABLE IF NOT EXISTS favorites (strongs TEXT PRIMARY KEY, lemma TEXT, definition TEXT)")
            db.execSQL("CREATE TABLE IF NOT EXISTS lexicon (strongs TEXT PRIMARY KEY, language TEXT, lemma TEXT, transliteration TEXT, definition TEXT)")
            db.execSQL("CREATE TABLE IF NOT EXISTS interlinear (book TEXT, chapter INTEGER, verse INTEGER, word_index INTEGER, original_text TEXT, translation TEXT, strongs TEXT, PRIMARY KEY(book, chapter, verse, word_index))")
            db.execSQL("CREATE TABLE IF NOT EXISTS highlights (book TEXT, chapter INTEGER, verse INTEGER, color INTEGER, PRIMARY KEY(book, chapter, verse))")
            db.execSQL("CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, book TEXT, chapter INTEGER, verse INTEGER, content TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)")
            db.execSQL("CREATE TABLE IF NOT EXISTS verses (book TEXT, chapter INTEGER, verse INTEGER, text TEXT, version TEXT, PRIMARY KEY(book, chapter, verse))")
            db.close()
        } catch (e: Exception) { e.printStackTrace() }
    }

    // --- NEW: TABLE INSPECTOR ENGINE ---
    fun getTableRows(tableName: String, limit: Int = 100): List<Map<String, String>> {
        val list = mutableListOf<Map<String, String>>()
        if (!dbFile.exists()) return list
        val db = getDb()
        try {
            val cursor = db.rawQuery("SELECT * FROM $tableName LIMIT $limit", null)
            val columns = cursor.columnNames
            while (cursor.moveToNext()) {
                val row = mutableMapOf<String, String>()
                columns.forEachIndexed { i, name ->
                    row[name] = cursor.getString(i) ?: "NULL"
                }
                list.add(row)
            }
            cursor.close()
        } catch (e: Exception) { Log.e("DB", "Inspect fail: ${e.message}") }
        finally { db.close() }
        return list
    }

    fun searchVerses(query: String): List<SearchResult> {
        if (!dbFile.exists() || query.length < 2) return emptyList()
        val list = mutableListOf<SearchResult>()
        val db = getDb()
        val refRegex = Regex("^([1-3]?\\s?[a-zA-Z]+)\\s?(\\d+)(?::(\\d+))?$", RegexOption.IGNORE_CASE)
        val match = refRegex.find(query.trim())
        if (match != null) {
            val bookPart = match.groupValues[1].lowercase().replace(" ", "")
            val resolvedBook = BIBLE_ABBREVIATIONS[bookPart] ?: books.find { it.name.lowercase() == bookPart }?.name
            if (resolvedBook != null) {
                val ch = match.groupValues[2]
                val vs = match.groupValues.getOrNull(3)
                val sql = if (vs.isNullOrEmpty()) "SELECT book, chapter, verse, text FROM verses WHERE book=? AND chapter=? LIMIT 100"
                          else "SELECT book, chapter, verse, text FROM verses WHERE book=? AND chapter=? AND verse=?"
                val args = if (vs.isNullOrEmpty()) arrayOf(resolvedBook, ch) else arrayOf(resolvedBook, ch, vs)
                val cursor = db.rawQuery(sql, args)
                while (cursor.moveToNext()) { list.add(SearchResult(cursor.getString(0), cursor.getInt(1), cursor.getInt(2), cursor.getString(3))) }
                cursor.close()
                if (list.isNotEmpty()) { db.close(); return list }
            }
        }
        val cursor = db.rawQuery("SELECT book, chapter, verse, text FROM verses WHERE text LIKE ? LIMIT 50", arrayOf("%$query%"))
        while (cursor.moveToNext()) { list.add(SearchResult(cursor.getString(0), cursor.getInt(1), cursor.getInt(2), cursor.getString(3))) }
        cursor.close(); db.close(); return list
    }

    fun getStats(): LibraryStats {
        if (!dbFile.exists()) return LibraryStats(0, 0, 0, 0, 0, 0, 0, 0.0)
        val db = getDb()
        val otList = books.filter { it.testament == "Old" }.joinToString(",") { "'${it.name}'" }
        val ntList = books.filter { it.testament == "New" }.joinToString(",") { "'${it.name}'" }
        val vOt = if (otList.isEmpty()) 0 else db.rawQuery("SELECT COUNT(*) FROM verses WHERE book IN ($otList)", null).use { if (it.moveToFirst()) it.getInt(0) else 0 }
        val vNt = if (ntList.isEmpty()) 0 else db.rawQuery("SELECT COUNT(*) FROM verses WHERE book IN ($ntList)", null).use { if (it.moveToFirst()) it.getInt(0) else 0 }
        val lHeb = db.rawQuery("SELECT COUNT(*) FROM lexicon WHERE language = 'hebrew'", null).use { if (it.moveToFirst()) it.getInt(0) else 0 }
        val lGk = db.rawQuery("SELECT COUNT(*) FROM lexicon WHERE language = 'greek'", null).use { if (it.moveToFirst()) it.getInt(0) else 0 }
        val n = db.rawQuery("SELECT COUNT(*) FROM notes", null).use { if (it.moveToFirst()) it.getInt(0) else 0 }
        val h = db.rawQuery("SELECT COUNT(*) FROM highlights", null).use { if (it.moveToFirst()) it.getInt(0) else 0 }
        val i = db.rawQuery("SELECT COUNT(*) FROM interlinear", null).use { if (it.moveToFirst()) it.getInt(0) else 0 }
        db.close()
        return LibraryStats(vOt, vNt, lHeb, lGk, n, h, i, dbFile.length() / (1024.0 * 1024.0))
    }

    fun clearTable(tableName: String) { val db = getDb(false); db.execSQL("DELETE FROM $tableName"); db.execSQL("VACUUM"); db.close() }
    fun factoryReset() { val db = getDb(false); db.execSQL("DELETE FROM verses"); db.execSQL("DELETE FROM lexicon"); db.execSQL("DELETE FROM interlinear"); db.execSQL("DELETE FROM highlights"); db.execSQL("DELETE FROM notes"); db.execSQL("DELETE FROM favorites"); db.execSQL("VACUUM"); db.close() }
    fun checkIntegrity(): String { if (!dbFile.exists()) return "DB Missing"; val db = getDb(); val cursor = db.rawQuery("PRAGMA integrity_check", null); var result = "Unknown"; if (cursor.moveToFirst()) result = cursor.getString(0); cursor.close(); db.close(); return result }
    fun vacuumDatabase() { val db = getDb(false); db.execSQL("VACUUM"); db.close() }

    fun saveFavorite(strongs: String, lemma: String, definition: String) { val db = getDb(false); db.execSQL("INSERT OR REPLACE INTO favorites (strongs, lemma, definition) VALUES (?, ?, ?)", arrayOf(strongs, lemma, definition)); db.close() }
    fun getFavorites(): List<Favorite> { val list = mutableListOf<Favorite>(); if (!dbFile.exists()) return list; val db = getDb(); val cursor = db.rawQuery("SELECT strongs, lemma, definition FROM favorites", null); while (cursor.moveToNext()) list.add(Favorite(cursor.getString(0), cursor.getString(1), cursor.getString(2))); cursor.close(); db.close(); return list }
    fun deleteFavorite(strongs: String) { val db = getDb(false); db.execSQL("DELETE FROM favorites WHERE strongs = ?", arrayOf(strongs)); db.close() }

    fun setHighlight(book: String, chapter: Int, verse: Int, color: Int) { val db = getDb(false); if (color == 0) db.execSQL("DELETE FROM highlights WHERE book=? AND chapter=? AND verse=?", arrayOf(book, chapter, verse)); else db.execSQL("INSERT OR REPLACE INTO highlights (book, chapter, verse, color) VALUES (?, ?, ?, ?)", arrayOf(book, chapter, verse, color)); db.close() }
    fun getHighlights(book: String, chapter: Int): Map<Int, Int> { val map = mutableMapOf<Int, Int>(); if (!dbFile.exists()) return map; val db = getDb(); val cursor = db.rawQuery("SELECT verse, color FROM highlights WHERE book=? AND chapter=?", arrayOf(book, chapter.toString())); while (cursor.moveToNext()) map[cursor.getInt(0)] = cursor.getInt(1); cursor.close(); db.close(); return map }

    fun saveNote(book: String, chapter: Int, verse: Int, content: String) { val db = getDb(false); db.execSQL("INSERT INTO notes (book, chapter, verse, content) VALUES (?, ?, ?)", arrayOf(book, chapter, verse, content)); db.close() }
    fun getNotes(book: String, chapter: Int, verse: Int): List<Note> { val list = mutableListOf<Note>(); if (!dbFile.exists()) return list; val db = getDb(); val cursor = db.rawQuery("SELECT id, content, timestamp FROM notes WHERE book=? AND chapter=? AND verse=? ORDER BY timestamp DESC", arrayOf(book, chapter.toString(), verse.toString())); while (cursor.moveToNext()) list.add(Note(cursor.getInt(0), book, chapter, verse, cursor.getString(1), cursor.getLong(2))); cursor.close(); db.close(); return list }

    fun getBookCompletion(): Map<String, Float> { val completion = mutableMapOf<String, Float>(); if (!dbFile.exists()) return completion; val db = getDb(); val cursor = db.rawQuery("SELECT book, COUNT(DISTINCT chapter) FROM verses GROUP BY book", null); while (cursor.moveToNext()) { val name = cursor.getString(0); val cachedChapters = cursor.getInt(1); val totalChapters = books.find { it.name == name }?.chapters ?: 1; completion[name] = cachedChapters.toFloat() / totalChapters.toFloat() }; cursor.close(); db.close(); return completion }

    fun getChapter(book: String, chapter: Int): List<Pair<Int, String>> { if (!dbFile.exists()) return emptyList(); val db = getDb(); val cursor = db.rawQuery("SELECT verse, text FROM verses WHERE book = ? AND chapter = ? ORDER BY verse ASC", arrayOf(book, chapter.toString())); val verses = mutableListOf<Pair<Int, String>>(); while (cursor.moveToNext()) verses.add(Pair(cursor.getInt(0), cursor.getString(1))); cursor.close(); db.close(); return verses }
    fun getInterlinear(book: String, chapter: Int, verse: Int): List<InterlinearWord> { if (!dbFile.exists()) return emptyList(); val db = getDb(); val cursor = db.rawQuery("SELECT original_text, strongs, translation FROM interlinear WHERE book = ? AND chapter = ? AND verse = ? ORDER BY word_index ASC", arrayOf(book, chapter.toString(), verse.toString())); val words = mutableListOf<InterlinearWord>(); while (cursor.moveToNext()) words.add(InterlinearWord(cursor.getString(0), cursor.getString(1), cursor.getString(2))); cursor.close(); db.close(); return words }
    fun getLexiconDetail(strongs: String): Pair<String, String> { if (!dbFile.exists()) return Pair("", ""); val db = getDb(); val cursor = db.rawQuery("SELECT lemma, definition FROM lexicon WHERE strongs = ?", arrayOf(strongs)); var res = Pair("", ""); if (cursor.moveToFirst()) res = Pair(cursor.getString(0) ?: "", cursor.getString(1) ?: ""); cursor.close(); db.close(); return res }

    suspend fun fetchChapter(book: String, chapter: Int, version: String = "NKJV") = withContext(Dispatchers.IO) {
        if (book in DeuterocanonRouting.NO_SOURCE_BOOKS) {
            throw IOException(DeuterocanonRouting.noSourceMessage(book))
        }
        val db = getDb(false); db.beginTransaction()
        try {
            if (book in WikisourceApocryphaScraper.SUPPORTED_BOOKS) {
                val scraper = WikisourceApocryphaScraper(client = client)
                scraper.scrapeChapter(book, chapter) { verseNum, text ->
                    db.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
                        arrayOf(book, chapter, verseNum, text, "KJV-Apocrypha"))
                }
            } else if (book == WikisourceEnochScraper.BOOK_NAME) {
                val scraper = WikisourceEnochScraper(client = client)
                scraper.scrapeChapter(chapter) { verseNum, text ->
                    db.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
                        arrayOf(book, chapter, verseNum, text, "R.H.Charles"))
                }
            } else {
                val scraper = BibleScraper(client = client)
                scraper.scrapeChapter(book, chapter, version) { verseNum, text ->
                    db.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
                        arrayOf(book, chapter, verseNum, text, version))
                }
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); db.close() }
    }

    suspend fun fetchInterlinear(book: String, chapter: Int) = withContext(Dispatchers.IO) {
        if (book in DeuterocanonRouting.NO_SOURCE_BOOKS || book in WikisourceApocryphaScraper.SUPPORTED_BOOKS || book == WikisourceEnochScraper.BOOK_NAME) {
            return@withContext
        }
        val db = getDb(false); db.beginTransaction()
        try {
            val scraper = BibleScraper(client = client)
            scraper.scrapeInterlinear(book, chapter) { verse, wordIdx, original, translation, strongs ->
                db.execSQL("INSERT OR REPLACE INTO interlinear (book, chapter, verse, word_index, original_text, translation, strongs) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    arrayOf(book, chapter, verse, wordIdx, original, translation, strongs))
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
        if (isG) scrapeGreekStrong(strongs) else scrapeHebrewStrong(strongs)
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
            if (def.isNotEmpty()) { val db = getDb(false); db.execSQL("INSERT OR REPLACE INTO lexicon (strongs, language, lemma, transliteration, definition) VALUES (?, 'greek', ?, ?, ?)", arrayOf(strongs, lemma, tr, def)); db.close() }
        } catch (e: Exception) { e.printStackTrace() }
    }

    private fun scrapeHebrewStrong(strongs: String) {
        val num = strongs.filter { it.isDigit() }
        val request = Request.Builder().url("https://biblehub.com/hebrew/$num.htm").header("User-Agent", "Mozilla/5.0").build()
        try {
            val response = client.newCall(request).execute()
            val doc = Jsoup.parse(response.body?.string() ?: return)
            val lemma = doc.select("span.hebrew").first()?.text()?.trim() ?: ""
            val tr = doc.select("span.translit").first()?.text()?.trim() ?: ""
            var def = doc.select("div.strongsnt").text().trim()
            if (def.isEmpty()) { val lb = doc.select("div#leftbox").first(); lb?.select("iframe, script, ins, .vheading")?.remove(); def = lb?.text()?.trim()?.take(3000) ?: "" }
            if (def.isNotEmpty()) { val db = getDb(false); db.execSQL("INSERT OR REPLACE INTO lexicon (strongs, language, lemma, transliteration, definition) VALUES (?, 'hebrew', ?, ?, ?)", arrayOf(strongs, lemma, tr, def)); db.close() }
        } catch (e: Exception) { e.printStackTrace() }
    }


}
