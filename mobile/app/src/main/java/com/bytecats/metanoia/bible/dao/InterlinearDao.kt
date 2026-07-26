package com.bytecats.metanoia.bible.dao

import android.database.sqlite.SQLiteDatabase
import com.bytecats.metanoia.models.InterlinearWord
import com.bytecats.metanoia.models.InterlinearWordWithVerse

class InterlinearDao(private val openDb: () -> SQLiteDatabase) {

    fun getInterlinear(book: String, chapter: Int, verse: Int): List<InterlinearWord> {
        val db = openDb()
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
        val db = openDb()
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
}
