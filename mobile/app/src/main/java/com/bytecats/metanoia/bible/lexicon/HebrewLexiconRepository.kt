package com.bytecats.metanoia.bible.lexicon

import android.database.sqlite.SQLiteDatabase
import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup

class HebrewLexiconRepository(
    private val client: OkHttpClient,
    private val openDb: () -> SQLiteDatabase
) {
    fun scrapeHebrewStrong(strongs: String) {
        val num = strongs.filter { it.isDigit() }
        val formattedStrongs = if (strongs.startsWith("H") || strongs.all { it.isDigit() }) "H$num" else strongs
        
        var lemma = ""
        var tr = ""
        var def = ""
        
        try {
            val request = Request.Builder().url("https://biblehub.com/hebrew/$num.htm").header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)").build()
            val response = client.newCall(request).execute()
            val html = response.body?.string() ?: ""
            if (response.isSuccessful && html.isNotEmpty()) {
                val doc = Jsoup.parse(html)
                lemma = doc.select("span.hebrew, span.greek").first()?.text()?.trim() ?: ""
                tr = doc.select("span.translit").first()?.text()?.trim() ?: ""
                def = doc.select("div.strongsnt, div.heading, div.vheading").text().trim()
                if (def.isEmpty()) { 
                    val lb = doc.select("div#leftbox, div.maincontent").first()
                    lb?.select("iframe, script, ins")?.remove()
                    def = lb?.text()?.trim()?.take(3000) ?: "" 
                }
                if (def.isEmpty()) {
                    def = doc.body().text().take(1500)
                }
            }
        } catch (e: Exception) {
            Log.e("HebrewLexicon", "Failed to scrape Hebrew strongs: $strongs", e)
        }
        
        // Fallback if empty
        if (def.isEmpty()) {
            def = "Definition unavailable (network error or not found). Strong's: $formattedStrongs"
            lemma = lemma.ifEmpty { "N/A" }
        }
        
        val db = openDb()
        db.execSQL("INSERT OR REPLACE INTO lexicon (strongs, language, lemma, transliteration, definition) VALUES (?, 'hebrew', ?, ?, ?)", arrayOf(formattedStrongs, lemma, tr, def))
        
        val altStrongs = if (formattedStrongs.startsWith("H")) num else "H$num"
        db.execSQL("INSERT OR REPLACE INTO lexicon (strongs, language, lemma, transliteration, definition) VALUES (?, 'hebrew', ?, ?, ?)", arrayOf(altStrongs, lemma, tr, def))
        
        if (strongs != formattedStrongs && strongs != altStrongs) {
            db.execSQL("INSERT OR REPLACE INTO lexicon (strongs, language, lemma, transliteration, definition) VALUES (?, 'hebrew', ?, ?, ?)", arrayOf(strongs, lemma, tr, def))
        }
        
        db.close() 
    }
}
