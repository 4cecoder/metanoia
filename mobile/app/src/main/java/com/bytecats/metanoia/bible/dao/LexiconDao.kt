package com.bytecats.metanoia.bible.dao

import android.database.sqlite.SQLiteDatabase
import com.bytecats.metanoia.models.LexiconEntry

class LexiconDao(private val openDb: () -> SQLiteDatabase) {

    fun getLexiconDetail(strongs: String): LexiconEntry {
        val db = openDb()
        val cursor = db.rawQuery("SELECT lemma, definition FROM lexicon WHERE strongs = ?", arrayOf(strongs))
        var res = LexiconEntry("", "")
        if (cursor.moveToFirst()) res = LexiconEntry(cursor.getString(0) ?: "", cursor.getString(1) ?: "")
        cursor.close(); db.close()
        return res
    }

    fun insertLexicon(strongs: String, language: String, lemma: String, transliteration: String, definition: String) {
        val db = openDb()
        db.execSQL(
            "INSERT OR REPLACE INTO lexicon (strongs, language, lemma, transliteration, definition) VALUES (?, ?, ?, ?, ?)",
            arrayOf(strongs, language, lemma, transliteration, definition)
        )
        db.close()
    }
}
