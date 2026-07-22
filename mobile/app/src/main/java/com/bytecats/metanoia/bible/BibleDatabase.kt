package com.bytecats.metanoia.bible

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import com.bytecats.metanoia.models.*
import java.io.File

class BibleDatabase(private val context: Context) {
    private val dbFile = File(context.filesDir, "bible.db")

    companion object {
        /**
         * SQLiteDatabase.openDatabase with OPEN_READWRITE alone throws
         * SQLITE_CANTOPEN (error 14) if dbFile doesn't exist yet — it does
         * NOT create it. On a clean install (no bible.db in filesDir yet),
         * that meant every write, including this class's own init() block,
         * threw immediately and was silently swallowed, so the file was
         * never created and every scrape/gateway fetch "succeeded" over the
         * network but failed to persist, with no visible error pointing at
         * the real cause.
         */
        fun openFlags(readOnly: Boolean): Int =
            if (readOnly) SQLiteDatabase.OPEN_READONLY
            else SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY
    }

    init {
        try {
            val db = open(false)
            db.execSQL("CREATE TABLE IF NOT EXISTS favorites (strongs TEXT PRIMARY KEY, lemma TEXT, definition TEXT)")
            db.execSQL("CREATE TABLE IF NOT EXISTS lexicon (strongs TEXT PRIMARY KEY, language TEXT, lemma TEXT, transliteration TEXT, definition TEXT)")
            db.execSQL("CREATE TABLE IF NOT EXISTS interlinear (book TEXT, chapter INTEGER, verse INTEGER, word_index INTEGER, original_text TEXT, translation TEXT, strongs TEXT, PRIMARY KEY(book, chapter, verse, word_index))")
            db.execSQL("CREATE TABLE IF NOT EXISTS highlights (book TEXT, chapter INTEGER, verse INTEGER, color INTEGER, PRIMARY KEY(book, chapter, verse))")
            db.execSQL("CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, book TEXT, chapter INTEGER, verse INTEGER, content TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)")
            db.execSQL("CREATE TABLE IF NOT EXISTS verses (book TEXT, chapter INTEGER, verse INTEGER, text TEXT, version TEXT, PRIMARY KEY(book, chapter, verse))")
            db.close()
        } catch (e: Exception) {
            Log.e("BibleDatabase", "Init failed: ${e.message}")
        }
    }

    fun exists(): Boolean = dbFile.exists()

    fun open(readOnly: Boolean = true): SQLiteDatabase {
        return SQLiteDatabase.openDatabase(dbFile.absolutePath, null, openFlags(readOnly))
    }

    fun sizeMb(): Double = dbFile.length() / (1024.0 * 1024.0)

    // --- Table inspection ---

    fun getTableRows(tableName: String, limit: Int = 100): List<Map<String, String>> {
        val list = mutableListOf<Map<String, String>>()
        if (!exists()) return list
        val db = open()
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
        } catch (e: Exception) {
            Log.e("BibleDatabase", "Inspect fail: ${e.message}")
        } finally { db.close() }
        return list
    }

    // --- Verses ---

    fun getChapter(book: String, chapter: Int): List<Verse> {
        if (!exists()) return emptyList()
        val db = open()
        val cursor = db.rawQuery(
            "SELECT verse, text FROM verses WHERE book = ? AND chapter = ? ORDER BY verse ASC",
            arrayOf(book, chapter.toString())
        )
        val verses = mutableListOf<Verse>()
        while (cursor.moveToNext()) verses.add(Verse(cursor.getInt(0), cursor.getString(1)))
        cursor.close(); db.close()
        return verses
    }

    fun insertVerses(book: String, chapter: Int, verses: List<Verse>, version: String) {
        val db = open(false)
        db.beginTransaction()
        try {
            for (v in verses) {
                db.execSQL(
                    "INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
                    arrayOf(book, chapter, v.number, v.text, version)
                )
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); db.close() }
    }

    fun searchVerses(query: String): List<SearchResult> {
        if (!exists() || query.length < 2) return emptyList()
        val refRegex = Regex("^([1-3]?\\s?[a-zA-Z]+)\\s?(\\d+)(?::(\\d+))?$", RegexOption.IGNORE_CASE)
        val list = mutableListOf<SearchResult>()
        val db = open()
        val match = refRegex.find(query.trim())
        if (match != null) {
            val bookPart = match.groupValues[1].lowercase().replace(" ", "")
            val resolvedBook = BIBLE_ABBREVIATIONS[bookPart]
                ?: BOOKS.find { it.name.lowercase() == bookPart }?.name
            if (resolvedBook != null) {
                val ch = match.groupValues[2]
                val vs = match.groupValues.getOrNull(3)
                val sql = if (vs.isNullOrEmpty())
                    "SELECT book, chapter, verse, text FROM verses WHERE book=? AND chapter=? LIMIT 100"
                else
                    "SELECT book, chapter, verse, text FROM verses WHERE book=? AND chapter=? AND verse=?"
                val args = if (vs.isNullOrEmpty()) arrayOf(resolvedBook, ch)
                else arrayOf(resolvedBook, ch, vs)
                val cursor = db.rawQuery(sql, args)
                while (cursor.moveToNext()) {
                    list.add(SearchResult(cursor.getString(0), cursor.getInt(1), cursor.getInt(2), cursor.getString(3)))
                }
                cursor.close()
                if (list.isNotEmpty()) { db.close(); return list }
            }
        }
        val cursor = db.rawQuery(
            "SELECT book, chapter, verse, text FROM verses WHERE text LIKE ? LIMIT 50",
            arrayOf("%$query%")
        )
        while (cursor.moveToNext()) {
            list.add(SearchResult(cursor.getString(0), cursor.getInt(1), cursor.getInt(2), cursor.getString(3)))
        }
        cursor.close(); db.close()
        return list
    }

    // --- Stats ---

    fun getStats(): LibraryStats {
        if (!exists()) return LibraryStats(0, 0, 0, 0, 0, 0, 0, 0.0)
        val db = open()
        val otList = BOOKS.filter { it.testament == "Old" }.joinToString(",") { "'${it.name}'" }
        val ntList = BOOKS.filter { it.testament == "New" }.joinToString(",") { "'${it.name}'" }
        val vOt = if (otList.isEmpty()) 0
        else db.rawQuery("SELECT COUNT(*) FROM verses WHERE book IN ($otList)", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        val vNt = if (ntList.isEmpty()) 0
        else db.rawQuery("SELECT COUNT(*) FROM verses WHERE book IN ($ntList)", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        val lHeb = db.rawQuery("SELECT COUNT(*) FROM lexicon WHERE language = 'hebrew'", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        val lGk = db.rawQuery("SELECT COUNT(*) FROM lexicon WHERE language = 'greek'", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        val n = db.rawQuery("SELECT COUNT(*) FROM notes", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        val h = db.rawQuery("SELECT COUNT(*) FROM highlights", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        val i = db.rawQuery("SELECT COUNT(*) FROM interlinear", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        db.close()
        return LibraryStats(vOt, vNt, lHeb, lGk, n, h, i, sizeMb())
    }

    // --- Admin ---

    fun clearTable(tableName: String) {
        val db = open(false); db.execSQL("DELETE FROM $tableName"); db.execSQL("VACUUM"); db.close()
    }

    fun factoryReset() {
        val db = open(false)
        db.execSQL("DELETE FROM verses"); db.execSQL("DELETE FROM lexicon")
        db.execSQL("DELETE FROM interlinear"); db.execSQL("DELETE FROM highlights")
        db.execSQL("DELETE FROM notes"); db.execSQL("DELETE FROM favorites")
        db.execSQL("VACUUM"); db.close()
    }

    fun checkIntegrity(): String {
        if (!exists()) return "DB Missing"
        val db = open()
        val cursor = db.rawQuery("PRAGMA integrity_check", null)
        var result = "Unknown"
        if (cursor.moveToFirst()) result = cursor.getString(0)
        cursor.close(); db.close()
        return result
    }

    fun vacuum() {
        val db = open(false); db.execSQL("VACUUM"); db.close()
    }

    // --- Favorites ---

    fun saveFavorite(strongs: String, lemma: String, definition: String) {
        val db = open(false)
        db.execSQL(
            "INSERT OR REPLACE INTO favorites (strongs, lemma, definition) VALUES (?, ?, ?)",
            arrayOf(strongs, lemma, definition)
        )
        db.close()
    }

    fun getFavorites(): List<Favorite> {
        if (!exists()) return emptyList()
        val list = mutableListOf<Favorite>()
        val db = open()
        val cursor = db.rawQuery("SELECT strongs, lemma, definition FROM favorites", null)
        while (cursor.moveToNext()) list.add(Favorite(cursor.getString(0), cursor.getString(1), cursor.getString(2)))
        cursor.close(); db.close()
        return list
    }

    fun deleteFavorite(strongs: String) {
        val db = open(false)
        db.execSQL("DELETE FROM favorites WHERE strongs = ?", arrayOf(strongs))
        db.close()
    }

    // --- Highlights ---

    fun setHighlight(book: String, chapter: Int, verse: Int, color: Int) {
        val db = open(false)
        if (color == 0) {
            db.execSQL(
                "DELETE FROM highlights WHERE book=? AND chapter=? AND verse=?",
                arrayOf(book, chapter.toString(), verse.toString())
            )
        } else {
            db.execSQL(
                "INSERT OR REPLACE INTO highlights (book, chapter, verse, color) VALUES (?, ?, ?, ?)",
                arrayOf(book, chapter.toString(), verse.toString(), color)
            )
        }
        db.close()
    }

    fun getHighlights(book: String, chapter: Int): Map<Int, Int> {
        if (!exists()) return emptyMap()
        val map = mutableMapOf<Int, Int>()
        val db = open()
        val cursor = db.rawQuery(
            "SELECT verse, color FROM highlights WHERE book=? AND chapter=?",
            arrayOf(book, chapter.toString())
        )
        while (cursor.moveToNext()) map[cursor.getInt(0)] = cursor.getInt(1)
        cursor.close(); db.close()
        return map
    }

    // --- Notes ---

    fun saveNote(book: String, chapter: Int, verse: Int, content: String) {
        val db = open(false)
        db.execSQL(
            "INSERT INTO notes (book, chapter, verse, content) VALUES (?, ?, ?, ?)",
            arrayOf(book, chapter.toString(), verse.toString(), content)
        )
        db.close()
    }

    fun getNotes(book: String, chapter: Int, verse: Int): List<Note> {
        if (!exists()) return emptyList()
        val list = mutableListOf<Note>()
        val db = open()
        val cursor = db.rawQuery(
            "SELECT id, content, timestamp FROM notes WHERE book=? AND chapter=? AND verse=? ORDER BY timestamp DESC",
            arrayOf(book, chapter.toString(), verse.toString())
        )
        while (cursor.moveToNext()) {
            list.add(Note(cursor.getInt(0), book, chapter, verse, cursor.getString(1), cursor.getLong(2)))
        }
        cursor.close(); db.close()
        return list
    }

    // --- Book completion ---

    fun getBookCompletion(): Map<String, Float> {
        if (!exists()) return emptyMap()
        val completion = mutableMapOf<String, Float>()
        val db = open()
        val cursor = db.rawQuery("SELECT book, COUNT(DISTINCT chapter) FROM verses GROUP BY book", null)
        while (cursor.moveToNext()) {
            val name = cursor.getString(0)
            val cachedChapters = cursor.getInt(1)
            val totalChapters = BOOKS.find { it.name == name }?.chapters ?: 1
            completion[name] = cachedChapters.toFloat() / totalChapters.toFloat()
        }
        cursor.close(); db.close()
        return completion
    }

    // --- Interlinear ---

    fun getInterlinear(book: String, chapter: Int, verse: Int): List<InterlinearWord> {
        if (!exists()) return emptyList()
        val db = open()
        val cursor = db.rawQuery(
            "SELECT original_text, strongs, translation FROM interlinear WHERE book = ? AND chapter = ? AND verse = ? ORDER BY word_index ASC",
            arrayOf(book, chapter.toString(), verse.toString())
        )
        val words = mutableListOf<InterlinearWord>()
        while (cursor.moveToNext()) words.add(InterlinearWord(cursor.getString(0), cursor.getString(1), cursor.getString(2)))
        cursor.close(); db.close()
        return words
    }

    fun insertInterlinearWords(book: String, chapter: Int, words: List<InterlinearWordWithVerse>) {
        val db = open(false)
        db.beginTransaction()
        try {
            for (w in words) {
                db.execSQL(
                    "INSERT OR REPLACE INTO interlinear (book, chapter, verse, word_index, original_text, translation, strongs) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    arrayOf(book, chapter, w.verse, w.wordIndex, w.original, w.translation, w.strongs)
                )
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); db.close() }
    }

    // --- Lexicon ---

    fun getLexiconDetail(strongs: String): LexiconEntry {
        if (!exists()) return LexiconEntry("", "")
        val db = open()
        val cursor = db.rawQuery("SELECT lemma, definition FROM lexicon WHERE strongs = ?", arrayOf(strongs))
        var res = LexiconEntry("", "")
        if (cursor.moveToFirst()) res = LexiconEntry(cursor.getString(0) ?: "", cursor.getString(1) ?: "")
        cursor.close(); db.close()
        return res
    }

    fun insertLexicon(strongs: String, language: String, lemma: String, transliteration: String, definition: String) {
        val db = open(false)
        db.execSQL(
            "INSERT OR REPLACE INTO lexicon (strongs, language, lemma, transliteration, definition) VALUES (?, ?, ?, ?, ?)",
            arrayOf(strongs, language, lemma, transliteration, definition)
        )
        db.close()
    }
}

data class InterlinearWordWithVerse(
    val verse: Int, val wordIndex: Int,
    val original: String, val translation: String, val strongs: String
)
