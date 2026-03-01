package com.bytecats.metanoia.bible

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class BibleBook(val name: String, val chapters: Int, val testament: String)
data class InterlinearWord(val original: String, val strongs: String, val translation: String)
data class Favorite(val strongs: String, val lemma: String, val definition: String)
data class Highlight(val book: String, val chapter: Int, val verse: Int, val color: Int)
data class Note(val id: Int = 0, val book: String, val chapter: Int, val verse: Int, val content: String, val timestamp: Long)
data class SearchResult(val book: String, val chapter: Int, val verse: Int, val text: String)

data class LibraryStats(
    val versesOt: Int, val versesNt: Int, 
    val lexiconHeb: Int, val lexiconGk: Int, 
    val notesCount: Int, val highlightsCount: Int,
    val interlinearCount: Int,
    val dbSizeMb: Double
)

class BibleManager(private val context: Context) {
    private val dbFile = File(context.filesDir, "bible.db")
    private val client = OkHttpClient()

    private val abbreviations = mapOf(
        "gen" to "Genesis", "ex" to "Exodus", "lev" to "Leviticus", "num" to "Numbers", "deut" to "Deuteronomy",
        "josh" to "Joshua", "judg" to "Judges", "ruth" to "Ruth", "1sam" to "1Samuel", "2sam" to "2Samuel",
        "1ki" to "1Kings", "2ki" to "2Kings", "1chr" to "1Chronicles", "2chr" to "2Chronicles", "ezr" to "Ezra",
        "neh" to "Nehemiah", "ps" to "Psalms", "prov" to "Proverbs", "eccl" to "Ecclesiastes", "song" to "SongofSolomon",
        "isa" to "Isaiah", "jer" to "Jeremiah", "lam" to "Lamentations", "eze" to "Ezekiel", "dan" to "Daniel",
        "hos" to "Hosea", "joe" to "Joel", "am" to "Amos", "oba" to "Obadiah", "jon" to "Jonah", "mic" to "Micah",
        "nah" to "Nahum", "hab" to "Habakkuk", "zep" to "Zephaniah", "hag" to "Haggai", "zec" to "Zechariah", "mal" to "Malachi",
        "matt" to "Matthew", "mk" to "Mark", "lk" to "Luke", "jn" to "John", "act" to "Acts", "rom" to "Romans",
        "1cor" to "1Corinthians", "2cor" to "2Corinthians", "gal" to "Galatians", "eph" to "Ephesians", "phi" to "Philippians",
        "col" to "Colossians", "1the" to "1Thessalonians", "2the" to "2Thessalonians", "1tim" to "1Timothy", "2tim" to "2Timothy",
        "tit" to "Titus", "phm" to "Philemon", "heb" to "Hebrews", "jam" to "James", "1pet" to "1Peter", "2pet" to "2Peter",
        "1jn" to "1John", "2jn" to "2John", "3jn" to "3John", "jud" to "Jude", "rev" to "Revelation"
    )

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
            val resolvedBook = abbreviations[bookPart] ?: books.find { it.name.lowercase() == bookPart }?.name
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

    suspend fun scrapeChapter(book: String, chapter: Int, version: String = "NKJV") = withContext(Dispatchers.IO) {
        val url = "https://www.biblegateway.com/passage/?search=$book+$chapter&version=$version&interface=print"
        val request = Request.Builder().url(url).header("User-Agent", "Mozilla/5.0").build()
        try {
            val response = client.newCall(request).execute()
            val doc = Jsoup.parse(response.body?.string() ?: return@withContext)
            doc.select("h1, h2, h3, h4, h5, h6").remove()
            val db = getDb(false); db.beginTransaction()
            try {
                doc.select("div.passage-text span.text").forEach { span ->
                    val verseNum = Regex("-(\\d+)$").find(span.className())?.groupValues?.get(1)?.toInt()
                    if (verseNum != null) {
                        span.select("sup, span.chapternum, span.versenum").remove()
                        db.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)", arrayOf(book, chapter, verseNum, span.text().trim(), version))
                    }
                }
                db.setTransactionSuccessful()
            } finally { db.endTransaction(); db.close() }
        } catch (e: Exception) { e.printStackTrace() }
    }

    suspend fun scrapeInterlinear(book: String, chapter: Int) = withContext(Dispatchers.IO) {
        val bookUrl = book.lowercase().replace(" ", "")
        val url = "https://biblehub.com/interlinear/$bookUrl/$chapter.htm"
        val isNT = books.find { it.name == book }?.testament == "New"
        val prefix = if (isNT) "G" else "H"
        val request = Request.Builder().url(url).header("User-Agent", "Mozilla/5.0").build()
        try {
            val response = client.newCall(request).execute()
            val doc = Jsoup.parse(response.body?.string() ?: return@withContext)
            val db = getDb(false); db.beginTransaction()
            try {
                var currentVerse = 0; var wordIdx = 0
                doc.select("table[class*=tablefloat]").forEach { table ->
                    val vSpan = table.select("span.reftop3, span.reftop").first()
                    if (vSpan != null) {
                        val vTxt = vSpan.text().filter { it.isDigit() }
                        if (vTxt.isNotEmpty()) { val nV = vTxt.toInt(); if (nV != currentVerse) { currentVerse = nV; wordIdx = 0 } }
                    }
                    if (currentVerse > 0) {
                        val orig = table.select("span.greek, span.heb, span.hebrew").first()?.text()?.trim()
                        if (orig != null && orig.isNotEmpty()) {
                            var strongs = table.select("span.pos, span.strongs").first()?.text()?.trim() ?: ""
                            if (strongs.isNotEmpty()) strongs = "$prefix${strongs.filter { it.isDigit() }}"
                            val trans = table.select("span.eng").first()?.text()?.trim() ?: ""
                            db.execSQL("INSERT OR REPLACE INTO interlinear (book, chapter, verse, word_index, original_text, translation, strongs) VALUES (?, ?, ?, ?, ?, ?, ?)", arrayOf(book, chapter, currentVerse, wordIdx, orig, trans, strongs))
                            wordIdx++
                        }
                    }
                }
                db.setTransactionSuccessful()
            } finally { db.endTransaction(); db.close() }
        } catch (e: Exception) { e.printStackTrace() }
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

    val books = listOf(
        BibleBook("Genesis", 50, "Old"), BibleBook("Exodus", 40, "Old"), BibleBook("Leviticus", 27, "Old"), BibleBook("Numbers", 36, "Old"), BibleBook("Deuteronomy", 34, "Old"), BibleBook("Joshua", 24, "Old"), BibleBook("Judges", 21, "Old"), BibleBook("Ruth", 4, "Old"), BibleBook("1Samuel", 31, "Old"), BibleBook("2Samuel", 24, "Old"), BibleBook("1Kings", 22, "Old"), BibleBook("2Kings", 25, "Old"), BibleBook("1Chronicles", 29, "Old"), BibleBook("2Chronicles", 36, "Old"), BibleBook("Ezra", 10, "Old"), BibleBook("Nehemiah", 13, "Old"), BibleBook("Tobit", 14, "Old"), BibleBook("Judith", 16, "Old"), BibleBook("Esther", 10, "Old"), BibleBook("1Meqabyan", 36, "Old"), BibleBook("2Meqabyan", 21, "Old"), BibleBook("3Meqabyan", 15, "Old"), BibleBook("Job", 42, "Old"), BibleBook("Psalms", 150, "Old"), BibleBook("Proverbs", 31, "Old"), BibleBook("Tegsas", 31, "Old"), BibleBook("Wisdom", 19, "Old"), BibleBook("Ecclesiastes", 12, "Old"), BibleBook("SongofSolomon", 8, "Old"), BibleBook("Sirach", 51, "Old"), BibleBook("Isaiah", 66, "Old"), BibleBook("Jeremiah", 52, "Old"), BibleBook("Lamentations", 5, "Old"), BibleBook("Ezekiel", 48, "Old"), BibleBook("Daniel", 12, "Old"), BibleBook("Hosea", 14, "Old"), BibleBook("Amos", 9, "Old"), BibleBook("Micah", 7, "Old"), BibleBook("Joel", 3, "Old"), BibleBook("Obadiah", 1, "Old"), BibleBook("Jonah", 4, "Old"), BibleBook("Nahum", 3, "Old"), BibleBook("Habakkuk", 3, "Old"), BibleBook("Zephaniah", 3, "Old"), BibleBook("Haggai", 2, "Old"), BibleBook("Zechariah", 14, "Old"), BibleBook("Malachi", 4, "Old"), BibleBook("Enoch", 108, "Old"), BibleBook("Jubilees", 50, "Old"),
        BibleBook("Matthew", 28, "New"), BibleBook("Mark", 16, "New"), BibleBook("Luke", 24, "New"), BibleBook("John", 21, "New"), BibleBook("Acts", 28, "New"), BibleBook("Romans", 16, "New"), BibleBook("1Corinthians", 16, "New"), BibleBook("2Corinthians", 13, "New"), BibleBook("Galatians", 6, "New"), BibleBook("Ephesians", 6, "New"), BibleBook("Philippians", 4, "New"), BibleBook("Colossians", 4, "New"), BibleBook("1Thessalonians", 5, "New"), BibleBook("2Thessalonians", 3, "New"), BibleBook("1Timothy", 6, "New"), BibleBook("2Timothy", 4, "New"), BibleBook("Titus", 3, "New"), BibleBook("Philemon", 1, "New"), BibleBook("Hebrews", 13, "New"), BibleBook("1Peter", 5, "New"), BibleBook("2Peter", 3, "New"), BibleBook("1John", 5, "New"), BibleBook("2John", 1, "New"), BibleBook("3John", 1, "New"), BibleBook("James", 5, "New"), BibleBook("Jude", 1, "New"), BibleBook("Revelation", 22, "New"),
        BibleBook("SirateTsion", 1, "Eth"), BibleBook("Tizaz", 1, "Eth"), BibleBook("Gitsiw", 1, "Eth"), BibleBook("Abtilis", 1, "Eth"), BibleBook("1Dominos", 1, "Eth"), BibleBook("2Dominos", 1, "Eth"), BibleBook("Qalementos", 1, "Eth"), BibleBook("Didasqalia", 1, "Eth")
    )
}
