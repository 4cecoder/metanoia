package com.bytecats.metanoia.bible

import com.bytecats.metanoia.models.strongsLanguagePrefix
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException

/**
 * BibleGateway scraper - primary source for verse text.
 *
 * Implements ChapterScraper interface for delegation.
 */
class BibleGatewayScraper(
    private val client: Call.Factory = OkHttpClient(),
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro)"
) : ChapterScraper {

    override suspend fun scrapeChapter(
        book: String, chapter: Int, version: String,
        onVerse: (Int, String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val url = "https://www.biblegateway.com/passage/?search=$book+$chapter&version=$version&interface=print"
        val request = Request.Builder().url(url).header("User-Agent", userAgent).build()
        val response = client.newCall(request).execute()

        if (!response.isSuccessful) {
            throw IOException("BibleGateway: HTTP ${response.code} for $book $chapter")
        }

        val body = response.body?.string()
            ?: throw IOException("BibleGateway: empty response body for $book $chapter")

        val doc = Jsoup.parse(body)
        doc.select("h1, h2, h3, h4, h5, h6").remove()

        doc.select("div.passage-text span.text").forEach { span ->
            // BibleGateway uses classes like "Gen-1-1", "Gen-1-2" (Book-Chapter-Verse)
            val className = span.className()
            val verseNum = Regex("-(\\d+)$").find(className)?.groupValues?.get(1)?.toInt()

            if (verseNum != null) {
                span.select("sup, span.chapternum, span.versenum").remove()
                val text = span.text().trim()
                if (text.isNotEmpty()) {
                    onVerse(verseNum, text)
                }
            }
        }
    }

    override fun getBaseUrl(): String = "www.biblegateway.com"

    override fun getPriority(): Int = 10 // Highest priority

    override fun supportsBook(book: String): Boolean {
        // BibleGateway supports most standard books
        // But NOT apocryphal books (Tobit, Judith, Wisdom, Sirach, Enoch, etc.)
        val apocryphaAndEthiopian = setOf(
            "Tobit", "Judith", "Wisdom", "Sirach",
            "Enoch", "Jubilees", "1Meqabyan", "2Meqabyan", "3Meqabyan",
            "Tegsas", "SirateTsion", "Tizaz", "Gitsiw", "Abtilis",
            "1Dominos", "2Dominos", "Qalementos", "Didasqalia"
        )
        return book !in apocryphaAndEthiopian
    }
}