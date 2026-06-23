package com.bytecats.metanoia.bible

import android.content.Context
import android.util.Log
import com.bytecats.metanoia.gateway.GatewayClient
import com.bytecats.metanoia.models.*
import com.bytecats.metanoia.settings.SettingsManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class BibleManager(private val context: Context) {
    val db = BibleDatabase(context)
    private val scraper = BibleScraper()
    private val settings = SettingsManager(context)
    val gateway: GatewayClient = GatewayClient { settings.gatewayUrl }

    val books: List<BibleBook> get() = BOOKS

    // --- Local DB passthroughs ---

    fun getTableRows(tableName: String, limit: Int = 100): List<Map<String, String>> =
        db.getTableRows(tableName, limit)

    fun getStats(): LibraryStats = db.getStats()

    fun clearTable(tableName: String) = db.clearTable(tableName)
    fun factoryReset() = db.factoryReset()
    fun checkIntegrity(): String = db.checkIntegrity()
    fun vacuumDatabase() = db.vacuum()

    fun searchVerses(query: String): List<SearchResult> = db.searchVerses(query)

    fun getChapter(book: String, chapter: Int): List<Verse> = db.getChapter(book, chapter)

    fun getInterlinear(book: String, chapter: Int, verse: Int): List<InterlinearWord> =
        db.getInterlinear(book, chapter, verse)

    fun getLexiconDetail(strongs: String): LexiconEntry = db.getLexiconDetail(strongs)

    fun saveFavorite(strongs: String, lemma: String, definition: String) =
        db.saveFavorite(strongs, lemma, definition)

    fun getFavorites(): List<Favorite> = db.getFavorites()
    fun deleteFavorite(strongs: String) = db.deleteFavorite(strongs)

    fun setHighlight(book: String, chapter: Int, verse: Int, color: Int) =
        db.setHighlight(book, chapter, verse, color)

    fun getHighlights(book: String, chapter: Int): Map<Int, Int> =
        db.getHighlights(book, chapter)

    fun saveNote(book: String, chapter: Int, verse: Int, content: String) =
        db.saveNote(book, chapter, verse, content)

    fun getNotes(book: String, chapter: Int, verse: Int): List<Note> =
        db.getNotes(book, chapter, verse)

    fun getBookCompletion(): Map<String, Float> = db.getBookCompletion()

    // --- Scraper passthroughs ---

    suspend fun scrapeChapter(book: String, chapter: Int, version: String = "NKJV") {
        scraper.scrapeChapter(book, chapter, version) { vNum, text ->
            db.open(false).apply {
                execSQL(
                    "INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
                    arrayOf(book, chapter, vNum, text, version)
                )
                close()
            }
        }
    }

    suspend fun scrapeInterlinear(book: String, chapter: Int) {
        scraper.scrapeInterlinear(book, chapter) { verse, wordIdx, orig, trans, strongs ->
            db.open(false).apply {
                execSQL(
                    "INSERT OR REPLACE INTO interlinear (book, chapter, verse, word_index, original_text, translation, strongs) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    arrayOf(book, chapter, verse, wordIdx, orig, trans, strongs)
                )
                close()
            }
        }
    }

    suspend fun scrapeStrong(strongs: String, bookName: String? = null) {
        scraper.scrapeLexicon(strongs, bookName) { lang, lemma, translit, def ->
            db.insertLexicon(strongs, lang, lemma, translit, def)
        }
    }

    // --- Gateway-backed methods ---

    suspend fun fetchChapter(book: String, chapter: Int, version: String = "NKJV"): List<Verse> {
        val local = db.getChapter(book, chapter)
        if (local.isNotEmpty()) return local

        if (settings.useGatewayBible) {
            try {
                val json = gateway.bibleChapter(book, chapter, version)
                if (json != null) {
                    val versesArr = json.optJSONArray("verses") ?: json.optJSONArray("data")
                    if (versesArr != null && versesArr.length() > 0) {
                        val verses = mutableListOf<Verse>()
                        for (i in 0 until versesArr.length()) {
                            val v = versesArr.getJSONObject(i)
                            val verseNum = v.optInt("verse", v.optInt("v", 0))
                            val text = v.optString("text", v.optString("t", ""))
                            if (verseNum > 0 && text.isNotEmpty()) {
                                verses.add(Verse(verseNum, text))
                            }
                        }
                        db.insertVerses(book, chapter, verses, version)
                        return verses
                    }
                }
            } catch (e: Exception) {
                Log.w("BibleManager", "Gateway chapter fetch failed: ${e.message}")
            }
        }

        scrapeChapter(book, chapter, version)
        return db.getChapter(book, chapter)
    }

    suspend fun fetchInterlinear(book: String, chapter: Int, verse: Int? = null): Map<Int, List<InterlinearWord>> {
        if (verse != null) {
            val local = db.getInterlinear(book, chapter, verse)
            if (local.isNotEmpty()) return mapOf(verse to local)
        }

        if (settings.useGatewayBible) {
            try {
                val json = gateway.bibleInterlinear(book, chapter, verse)
                if (json != null) {
                    val result = mutableMapOf<Int, List<InterlinearWord>>()
                    val wordsArr = json.optJSONArray("words") ?: json.optJSONArray("interlinear")
                    if (wordsArr != null) {
                        val words = mutableListOf<InterlinearWordWithVerse>()
                        for (i in 0 until wordsArr.length()) {
                            val w = wordsArr.getJSONObject(i)
                            val vNum = w.optInt("verse", w.optInt("v", verse ?: 1))
                            val orig = w.optString("original", w.optString("hebrew", w.optString("greek", "")))
                            val strongs = w.optString("strongs", "")
                            val trans = w.optString("translation", w.optString("english", ""))
                            if (orig.isNotEmpty()) {
                                words.add(InterlinearWordWithVerse(vNum, i, orig, trans, strongs))
                                result.getOrPut(vNum) { mutableListOf() }
                                (result[vNum] as MutableList).add(InterlinearWord(orig, strongs, trans))
                            }
                        }
                        db.insertInterlinearWords(book, chapter, words)
                        if (result.isNotEmpty()) return result
                    }
                }
            } catch (e: Exception) {
                Log.w("BibleManager", "Gateway interlinear fetch failed: ${e.message}")
            }
        }

        scrapeInterlinear(book, chapter)
        return if (verse != null) mapOf(verse to db.getInterlinear(book, chapter, verse)) else emptyMap()
    }

    suspend fun fetchLexicon(strongs: String, bookName: String? = null): LexiconEntry {
        val local = db.getLexiconDetail(strongs)
        if (local.lemma.isNotEmpty() || local.definition.isNotEmpty()) return local

        if (settings.useGatewayBible) {
            try {
                val json = gateway.bibleLexicon(strongs)
                if (json != null) {
                    val lemma = json.optString("lemma", json.optString("word", ""))
                    val def = json.optString("definition", json.optString("def", ""))
                    val lang = json.optString("language", if (strongs.startsWith("G")) "greek" else "hebrew")
                    if (lemma.isNotEmpty() || def.isNotEmpty()) {
                        db.insertLexicon(strongs, lang, lemma, json.optString("transliteration", ""), def)
                        return LexiconEntry(lemma, def)
                    }
                }
            } catch (e: Exception) {
                Log.w("BibleManager", "Gateway lexicon fetch failed: ${e.message}")
            }
        }

        scrapeStrong(strongs, bookName)
        return db.getLexiconDetail(strongs)
    }

    suspend fun searchGateway(query: String): List<SearchResult> {
        if (!settings.useGatewayBible) return withContext(Dispatchers.IO) { db.searchVerses(query) }
        try {
            val json = gateway.bibleSearch(query, 50)
            if (json != null) {
                val arr = json.optJSONArray("results") ?: json.optJSONArray("matches")
                if (arr != null) {
                    val results = mutableListOf<SearchResult>()
                    for (i in 0 until arr.length()) {
                        val r = arr.getJSONObject(i)
                        results.add(SearchResult(
                            r.optString("book"), r.optInt("chapter"), r.optInt("verse"), r.optString("text")
                        ))
                    }
                    return results
                }
            }
        } catch (e: Exception) {
            Log.w("BibleManager", "Gateway search failed, using local: ${e.message}")
        }
        return withContext(Dispatchers.IO) { db.searchVerses(query) }
    }

    fun isGatewayAvailable(): Boolean = gateway.health()
}
