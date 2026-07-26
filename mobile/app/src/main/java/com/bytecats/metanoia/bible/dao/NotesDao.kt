package com.bytecats.metanoia.bible.dao

import android.database.sqlite.SQLiteDatabase
import com.bytecats.metanoia.models.Note

class NotesDao(private val openDb: () -> SQLiteDatabase) {

    fun saveNote(book: String, chapter: Int, verse: Int, content: String) {
        val db = openDb()
        db.execSQL(
            "INSERT INTO notes (book, chapter, verse, content) VALUES (?, ?, ?, ?)",
            arrayOf(book, chapter.toString(), verse.toString(), content)
        )
        db.close()
    }

    fun getNotes(book: String, chapter: Int, verse: Int): List<Note> {
        val list = mutableListOf<Note>()
        val db = openDb()
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
}
