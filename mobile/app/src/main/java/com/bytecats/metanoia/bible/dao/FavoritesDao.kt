package com.bytecats.metanoia.bible.dao

import android.database.sqlite.SQLiteDatabase
import com.bytecats.metanoia.models.Favorite

class FavoritesDao(private val openDb: () -> SQLiteDatabase) {

    fun saveFavorite(strongs: String, lemma: String, definition: String) {
        val db = openDb()
        db.execSQL(
            "INSERT OR REPLACE INTO favorites (strongs, lemma, definition) VALUES (?, ?, ?)",
            arrayOf(strongs, lemma, definition)
        )
        db.close()
    }

    fun getFavorites(): List<Favorite> {
        val list = mutableListOf<Favorite>()
        val db = openDb()
        val cursor = db.rawQuery("SELECT strongs, lemma, definition FROM favorites", null)
        while (cursor.moveToNext()) list.add(Favorite(cursor.getString(0), cursor.getString(1), cursor.getString(2)))
        cursor.close(); db.close()
        return list
    }

    fun deleteFavorite(strongs: String) {
        val db = openDb()
        db.execSQL("DELETE FROM favorites WHERE strongs = ?", arrayOf(strongs))
        db.close()
    }
}
