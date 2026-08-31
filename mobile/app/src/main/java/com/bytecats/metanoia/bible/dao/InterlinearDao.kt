package com.bytecats.metanoia.bible.dao

import android.database.sqlite.SQLiteDatabase
import com.bytecats.metanoia.models.InterlinearWord
import com.bytecats.metanoia.models.InterlinearWordWithVerse

class InterlinearDao(private val openDb: () -> SQLiteDatabase) {

    /**
     * `preferredSource` picks which text ('MT'/'LXX'/'GNT' -- see
     * BibleDatabase's interlinear schema comment) to read when a verse has
     * more than one cached. Falls back to whichever source IS cached if the
     * preferred one isn't (e.g. LXX not yet scraped/bundled for a given
     * chapter) -- same pattern as src/main.zig's load_chapter_into_study.
     * Null means "no preference, just pick one deterministically."
     */
    fun getInterlinear(book: String, chapter: Int, verse: Int, preferredSource: String? = null): List<InterlinearWord> {
        val db = openDb()
        val pref = preferredSource ?: ""
        val cursor = db.rawQuery(
            "SELECT original_text, strongs, translation FROM interlinear WHERE book = ? AND chapter = ? AND verse = ? " +
                "AND source = (" +
                "  SELECT source FROM interlinear i2 WHERE i2.book=interlinear.book AND i2.chapter=interlinear.chapter " +
                "  AND i2.verse=interlinear.verse ORDER BY (source != ?), source LIMIT 1" +
                ") ORDER BY word_index ASC",
            arrayOf(book, chapter.toString(), verse.toString(), pref)
        )
        val words = mutableListOf<InterlinearWord>()
        while (cursor.moveToNext()) words.add(InterlinearWord(cursor.getString(0), cursor.getString(1), cursor.getString(2)))
        cursor.close(); db.close()
        return words
    }

    fun insertInterlinearWords(book: String, chapter: Int, words: List<InterlinearWordWithVerse>, source: String) {
        val db = openDb()
        db.beginTransaction()
        try {
            for (w in words) {
                db.execSQL(
                    "INSERT OR REPLACE INTO interlinear (book, chapter, verse, word_index, original_text, translation, strongs, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    arrayOf(book, chapter, w.verse, w.wordIndex, w.original, w.translation, w.strongs, source)
                )
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); db.close() }
    }
}
