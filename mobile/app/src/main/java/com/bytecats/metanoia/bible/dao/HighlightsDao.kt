package com.bytecats.metanoia.bible.dao

import android.database.sqlite.SQLiteDatabase

class HighlightsDao(private val openDb: () -> SQLiteDatabase) {

    fun setHighlight(book: String, chapter: Int, verse: Int, color: Int) {
        val db = openDb()
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
        val map = mutableMapOf<Int, Int>()
        val db = openDb()
        val cursor = db.rawQuery(
            "SELECT verse, color FROM highlights WHERE book=? AND chapter=?",
            arrayOf(book, chapter.toString())
        )
        while (cursor.moveToNext()) map[cursor.getInt(0)] = cursor.getInt(1)
        cursor.close(); db.close()
        return map
    }
}
