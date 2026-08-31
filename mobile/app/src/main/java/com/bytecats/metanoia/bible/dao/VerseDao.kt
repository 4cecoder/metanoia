package com.bytecats.metanoia.bible.dao

import android.database.sqlite.SQLiteDatabase
import android.util.Log
import com.bytecats.metanoia.models.*

class VerseDao(private val openDb: () -> SQLiteDatabase) {

    // Content-DB tables only -- favorites/highlights/notes moved to the
    // separate library DB (see BibleDatabase's LIBRARY_TABLES and its
    // volatility-split doc comment).
    private val allowedTables = setOf("lexicon", "interlinear", "verses")

    private fun validateTableName(tableName: String) {
        require(tableName in allowedTables) { "Invalid table name: $tableName" }
    }

    /**
     * `preferredVersion` ('NKJV'/'LXXE', see BibleDatabase's verses schema
     * comment) picks which English translation to read when a verse has
     * more than one cached, falling back to whichever version IS cached if
     * the preferred one isn't (e.g. the deuterocanon only ever has 'LXXE',
     * the New Testament only ever has 'NKJV') -- same fallback pattern as
     * getInterlinear(). Null means "no preference, just pick one
     * deterministically."
     */
    fun getChapter(book: String, chapter: Int, preferredVersion: String? = null): List<Verse> {
        val db = openDb()
        val pref = preferredVersion ?: ""
        val cursor = db.rawQuery(
            "SELECT verse, text FROM verses WHERE book = ? AND chapter = ? " +
                "AND version = (" +
                "  SELECT version FROM verses v2 WHERE v2.book=verses.book AND v2.chapter=verses.chapter " +
                "  ORDER BY (version != ?), version LIMIT 1" +
                ") ORDER BY verse ASC",
            arrayOf(book, chapter.toString(), pref)
        )
        val verses = mutableListOf<Verse>()
        while (cursor.moveToNext()) verses.add(Verse(cursor.getInt(0), cursor.getString(1)))
        cursor.close(); db.close()
        return verses
    }

    fun insertVerses(book: String, chapter: Int, verses: List<Verse>, version: String) {
        val db = openDb()
        db.beginTransaction()
        try {
            val stmt = db.compileStatement("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)")
            for (v in verses) {
                stmt.bindString(1, book)
                stmt.bindLong(2, chapter.toLong())
                stmt.bindLong(3, v.number.toLong())
                stmt.bindString(4, v.text)
                stmt.bindString(5, version)
                stmt.execute()
                stmt.clearBindings()
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); db.close() }
    }

    fun searchVerses(query: String): List<SearchResult> {
        if (query.length < 2) return emptyList()
        val refRegex = Regex("^([1-3]?\\s?[a-zA-Z]+)\\s?(\\d+)(?::(\\d+))?$", RegexOption.IGNORE_CASE)
        val list = mutableListOf<SearchResult>()
        val db = openDb()
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
            "SELECT book, chapter, verse, text FROM verses_fts WHERE text MATCH ? LIMIT 50",
            arrayOf("$query*")
        )
        while (cursor.moveToNext()) {
            list.add(SearchResult(cursor.getString(0), cursor.getInt(1), cursor.getInt(2), cursor.getString(3)))
        }
        cursor.close(); db.close()
        return list
    }

    fun getStats(): LibraryStats {
        val db = openDb()
        var vOt = 0
        var vNt = 0
        val cursor = db.rawQuery("SELECT book, COUNT(*) FROM verses GROUP BY book", null)
        while (cursor.moveToNext()) {
            val book = cursor.getString(0)
            val count = cursor.getInt(1)
            val testament = BOOKS.find { it.name == book }?.testament
            if (testament == "Old") vOt += count
            else if (testament == "New") vNt += count
        }
        cursor.close()
        val lHeb = db.rawQuery("SELECT COUNT(*) FROM lexicon WHERE language = 'hebrew'", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        val lGk = db.rawQuery("SELECT COUNT(*) FROM lexicon WHERE language = 'greek'", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        val i = db.rawQuery("SELECT COUNT(*) FROM interlinear", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        db.close()
        // notesCount/highlightsCount live in the library DB, not here --
        // BibleDatabase.getStats() fills those in after calling this.
        return LibraryStats(vOt, vNt, lHeb, lGk, 0, 0, i, 0.0)
    }

    fun getTableRows(tableName: String, limit: Int): List<Map<String, String>> {
        val list = mutableListOf<Map<String, String>>()
        validateTableName(tableName)
        val db = openDb()
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
            Log.e("VerseDao", "Inspect fail: ${e.message}")
        } finally { db.close() }
        return list
    }

    fun clearTable(tableName: String) {
        validateTableName(tableName)
        val db = openDb(); db.execSQL("DELETE FROM $tableName"); db.execSQL("VACUUM"); db.close()
    }

    /** Clears content tables only (verses/lexicon/interlinear). Personal
     * data (highlights/notes/favorites, now in the library DB) is cleared
     * separately by BibleDatabase.factoryReset(). */
    fun clearContentTables() {
        val db = openDb()
        db.execSQL("DELETE FROM verses"); db.execSQL("DELETE FROM lexicon")
        db.execSQL("DELETE FROM interlinear")
        db.execSQL("VACUUM"); db.close()
    }

    fun checkIntegrity(): String {
        val db = openDb()
        val cursor = db.rawQuery("PRAGMA integrity_check", null)
        var result = "Unknown"
        if (cursor.moveToFirst()) result = cursor.getString(0)
        cursor.close(); db.close()
        return result
    }

    fun vacuum() {
        val db = openDb(); db.execSQL("VACUUM"); db.close()
    }

    fun getBookCompletion(): Map<String, Float> {
        val completion = mutableMapOf<String, Float>()
        val db = openDb()
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

    fun getChapterWordCounts(book: String): Map<Int, Int> {
        val db = openDb()
        val cursor = db.rawQuery(
            "SELECT chapter, text FROM verses WHERE book = ?",
            arrayOf(book)
        )
        val wordCounts = mutableMapOf<Int, Int>()
        while (cursor.moveToNext()) {
            val chapter = cursor.getInt(0)
            val text = cursor.getString(1)
            val words = com.bytecats.metanoia.bible.ReadingStats.calculateWordCount(text)
            wordCounts[chapter] = (wordCounts[chapter] ?: 0) + words
        }
        cursor.close(); db.close()
        return wordCounts
    }

    fun getDownloadedChapters(book: String): Set<Int> {
        val downloaded = mutableSetOf<Int>()
        val db = openDb()
        val cursor = db.rawQuery("SELECT DISTINCT chapter FROM verses WHERE book = ?", arrayOf(book))
        while (cursor.moveToNext()) {
            downloaded.add(cursor.getInt(0))
        }
        cursor.close(); db.close()
        return downloaded
    }
}
