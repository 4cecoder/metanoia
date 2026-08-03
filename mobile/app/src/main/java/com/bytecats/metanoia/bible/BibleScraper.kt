package com.bytecats.metanoia.bible

import com.bytecats.metanoia.models.strongsLanguagePrefix
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException

class BibleScraper(
    // Typed as the Call.Factory interface (which OkHttpClient implements)
    // rather than the concrete OkHttpClient class, so tests can substitute a
    // lightweight fake to simulate network failures without needing a real
    // HTTP stack or a class-mocking framework.
    private val client: Call.Factory = OkHttpClient(),
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro)"
) {
    // NOTE: none of the scrape* functions below catch-and-swallow their own
    // network/parse exceptions. A failed fetch (timeout, HTTP error, empty
    // body, or a Strong's page with no parseable definition) throws instead
    // of returning silently, so callers (BibleManager) can distinguish "still
    // loading" from "actually failed" and surface an error to the UI instead
    // of leaving the caller waiting forever with no signal.

    suspend fun scrapeChapter(
        book: String, chapter: Int, version: String = "NKJV",
        onVerse: (Int, String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val url = "https://www.biblegateway.com/passage/?search=$book+$chapter&version=$version&interface=print"
        val request = Request.Builder().url(url).header("User-Agent", userAgent).build()
        val response = client.newCall(request).execute()
        val body = response.body?.string()
            ?: throw IOException("scrapeChapter: empty response body for $book $chapter ($version)")
        val doc = Jsoup.parse(body)
        doc.select("h1, h2, h3, h4, h5, h6").remove()
        doc.select("div.passage-text span.text").forEach { span ->
            // Get classes as a single string (Jsoup returns space-separated)
            val className = span.className()
            // Match any class that ends with dash-digit pattern
            val verseNum = Regex("\\b(\\d+)\\b").find(className)?.groupValues?.get(1)?.toInt()
            if (verseNum != null) {
                span.select("sup, span.chapternum, span.versenum").remove()
                onVerse(verseNum, span.text().trim())
            }
        }
    }

    suspend fun scrapeInterlinear(
        book: String, chapter: Int,
        onWord: (verse: Int, wordIndex: Int, original: String, translation: String, strongs: String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val bookUrl = interlinearSlug(book)
        val url = "https://biblehub.com/interlinear/$bookUrl/$chapter.htm"
        // Derived from the shared BOOKS testament data (models/BibleConstants.kt)
        // rather than a locally-hardcoded OT/NT list, so it cannot drift.
        val prefix = strongsLanguagePrefix(book)
        val request = Request.Builder().url(url).header("User-Agent", userAgent).build()
        val response = client.newCall(request).execute()
        if (!response.isSuccessful) {
            throw IOException("scrapeInterlinear: HTTP ${response.code} for $book $chapter ($url)")
        }
        val body = response.body?.string()
            ?: throw IOException("scrapeInterlinear: empty response body for $book $chapter")
        val doc = Jsoup.parse(body)
        var currentVerse = 0; var wordIdx = 0
        val tables = doc.select("table[class*=tablefloat], div.interlinear")
        tables.forEach { element ->
            val vSpan = element.select("span.reftop3, span.reftop, a.vref").first()
            if (vSpan != null) {
                val vTxt = vSpan.text().filter { it.isDigit() }
                if (vTxt.isNotEmpty()) {
                    val nV = vTxt.toInt()
                    if (nV != currentVerse) { currentVerse = nV; wordIdx = 0 }
                }
            }
            if (currentVerse > 0) {
                val orig = element.select("span.greek, span.heb, span.hebrew").first()?.text()?.trim()
                if (orig != null && orig.isNotEmpty()) {
                    var strongs = element.select("span.pos, span.strongs, a[href*='/strongs/']").first()?.text()?.trim() ?: ""
                    if (strongs.isNotEmpty()) {
                        strongs = "$prefix${strongs.filter { it.isDigit() }}"
                    }
                    val trans = element.select("span.eng").first()?.text()?.trim() ?: ""
                    onWord(currentVerse, wordIdx, orig, trans, strongs)
                    wordIdx++
                }
            }
        }
    }

    /**
     * BibleHub interlinear URLs use a specific slug format:
     * - lowercase, no spaces
     * - numbered books get an underscore after the digit: 1_corinthians, 2_samuel
     * - "Song of Solomon" is mapped to "songs"
     */
    private fun interlinearSlug(book: String): String {
        val normalized = book.lowercase().replace(" ", "")
        return when (normalized) {
            "songofsolomon", "songofsongs", "songofsong" -> "songs"
            else -> normalized.replace(Regex("^(\\d+)([a-z]+)$")) { m ->
                "${m.groupValues[1]}_${m.groupValues[2]}"
            }
        }
    }

    suspend fun scrapeLexicon(
        strongs: String, bookName: String? = null,
        onResult: (language: String, lemma: String, transliteration: String, definition: String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val isG = if (bookName != null) strongsLanguagePrefix(bookName) == "G"
        else strongs.startsWith("G")
        if (isG) scrapeGreekStrong(strongs, onResult)
        else scrapeHebrewStrong(strongs, onResult)
    }

    private fun scrapeGreekStrong(
        strongs: String,
        onResult: (language: String, lemma: String, transliteration: String, definition: String) -> Unit
    ) {
        val num = strongs.filter { it.isDigit() }
        val request = Request.Builder().url("https://biblehub.com/greek/$num.htm")
            .header("User-Agent", userAgent).build()
        val response = client.newCall(request).execute()
        val body = response.body?.string()
            ?: throw IOException("scrapeGreekStrong: empty response body for $strongs")
        val doc = Jsoup.parse(body)
        val lemma = doc.select("span.greek").first()?.text()?.trim() ?: ""
        val tr = doc.select("span.translit").first()?.text()?.trim() ?: ""
        var def = doc.select("div.strongsnt").text().trim()
        if (def.isEmpty()) {
            val lb = doc.select("div#leftbox").first()
            lb?.select("iframe, script, ins, .vheading")?.remove()
            def = lb?.text()?.trim()?.take(3000) ?: ""
        }
        if (def.isNotEmpty()) onResult("greek", lemma, tr, def)
        else throw IOException("scrapeGreekStrong: no definition found for $strongs")
    }

    private fun scrapeHebrewStrong(
        strongs: String,
        onResult: (language: String, lemma: String, transliteration: String, definition: String) -> Unit
    ) {
        val num = strongs.filter { it.isDigit() }
        val request = Request.Builder().url("https://biblehub.com/hebrew/$num.htm")
            .header("User-Agent", userAgent).build()
        val response = client.newCall(request).execute()
        val body = response.body?.string()
            ?: throw IOException("scrapeHebrewStrong: empty response body for $strongs")
        val doc = Jsoup.parse(body)
        val lemma = doc.select("span.hebrew").first()?.text()?.trim() ?: ""
        val tr = doc.select("span.translit").first()?.text()?.trim() ?: ""
        var def = doc.select("div.strongsnt").text().trim()
        if (def.isEmpty()) {
            val lb = doc.select("div#leftbox").first()
            lb?.select("iframe, script, ins, .vheading")?.remove()
            def = lb?.text()?.trim()?.take(3000) ?: ""
        }
        if (def.isNotEmpty()) onResult("hebrew", lemma, tr, def)
        else throw IOException("scrapeHebrewStrong: no definition found for $strongs")
    }
}
