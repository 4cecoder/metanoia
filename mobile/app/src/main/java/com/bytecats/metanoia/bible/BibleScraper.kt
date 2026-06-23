package com.bytecats.metanoia.bible

import android.util.Log
import com.bytecats.metanoia.models.BOOKS
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class BibleScraper(
    private val client: OkHttpClient = OkHttpClient(),
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro)"
) {
    private val tag = "BibleScraper"

    suspend fun scrapeChapter(
        book: String, chapter: Int, version: String = "NKJV",
        onVerse: (Int, String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val url = "https://www.biblegateway.com/passage/?search=$book+$chapter&version=$version&interface=print"
        val request = Request.Builder().url(url).header("User-Agent", userAgent).build()
        try {
            val response = client.newCall(request).execute()
            val doc = Jsoup.parse(response.body?.string() ?: return@withContext)
            doc.select("h1, h2, h3, h4, h5, h6").remove()
            doc.select("div.passage-text span.text").forEach { span ->
                val verseNum = Regex("-(\\d+)$").find(span.className())?.groupValues?.get(1)?.toInt()
                if (verseNum != null) {
                    span.select("sup, span.chapternum, span.versenum").remove()
                    onVerse(verseNum, span.text().trim())
                }
            }
        } catch (e: Exception) {
            Log.e(tag, "scrapeChapter failed: ${e.message}")
        }
    }

    suspend fun scrapeInterlinear(
        book: String, chapter: Int,
        onWord: (verse: Int, wordIndex: Int, original: String, translation: String, strongs: String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val bookUrl = book.lowercase().replace(" ", "")
        val url = "https://biblehub.com/interlinear/$bookUrl/$chapter.htm"
        val isNT = BOOKS.find { it.name == book }?.testament == "New"
        val prefix = if (isNT) "G" else "H"
        val request = Request.Builder().url(url).header("User-Agent", userAgent).build()
        try {
            val response = client.newCall(request).execute()
            val doc = Jsoup.parse(response.body?.string() ?: return@withContext)
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
        } catch (e: Exception) {
            Log.e(tag, "scrapeInterlinear failed: ${e.message}")
        }
    }

    suspend fun scrapeLexicon(
        strongs: String, bookName: String? = null,
        onResult: (language: String, lemma: String, transliteration: String, definition: String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val isG = if (bookName != null) BOOKS.find { it.name == bookName }?.testament == "New"
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
        try {
            val response = client.newCall(request).execute()
            val doc = Jsoup.parse(response.body?.string() ?: return)
            val lemma = doc.select("span.greek").first()?.text()?.trim() ?: ""
            val tr = doc.select("span.translit").first()?.text()?.trim() ?: ""
            var def = doc.select("div.strongsnt").text().trim()
            if (def.isEmpty()) {
                val lb = doc.select("div#leftbox").first()
                lb?.select("iframe, script, ins, .vheading")?.remove()
                def = lb?.text()?.trim()?.take(3000) ?: ""
            }
            if (def.isNotEmpty()) onResult("greek", lemma, tr, def)
        } catch (e: Exception) {
            Log.e(tag, "scrapeGreekStrong failed: ${e.message}")
        }
    }

    private fun scrapeHebrewStrong(
        strongs: String,
        onResult: (language: String, lemma: String, transliteration: String, definition: String) -> Unit
    ) {
        val num = strongs.filter { it.isDigit() }
        val request = Request.Builder().url("https://biblehub.com/hebrew/$num.htm")
            .header("User-Agent", userAgent).build()
        try {
            val response = client.newCall(request).execute()
            val doc = Jsoup.parse(response.body?.string() ?: return)
            val lemma = doc.select("span.hebrew").first()?.text()?.trim() ?: ""
            val tr = doc.select("span.translit").first()?.text()?.trim() ?: ""
            var def = doc.select("div.strongsnt").text().trim()
            if (def.isEmpty()) {
                val lb = doc.select("div#leftbox").first()
                lb?.select("iframe, script, ins, .vheading")?.remove()
                def = lb?.text()?.trim()?.take(3000) ?: ""
            }
            if (def.isNotEmpty()) onResult("hebrew", lemma, tr, def)
        } catch (e: Exception) {
            Log.e(tag, "scrapeHebrewStrong failed: ${e.message}")
        }
    }
}
