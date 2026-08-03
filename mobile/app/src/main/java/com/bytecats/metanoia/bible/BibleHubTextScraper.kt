package com.bytecats.metanoia.bible

import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException

/**
 * BibleHub text scraper - secondary source for verse text.
 *
 * Implements ChapterScraper interface for delegation.
 */
class BibleHubTextScraper(
    private val client: Call.Factory = OkHttpClient(),
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro)"
) : ChapterScraper {

    override suspend fun scrapeChapter(
        book: String, chapter: Int, version: String,
        onVerse: (Int, String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val bookSlug = interlinearSlug(book)
        val url = "https://biblehub.com/text/$bookSlug/$chapter.htm"
        val request = Request.Builder().url(url).header("User-Agent", userAgent).build()
        val response = client.newCall(request).execute()

        if (!response.isSuccessful) {
            throw IOException("BibleHub Text: HTTP ${response.code} for $book $chapter")
        }

        val body = response.body?.string()
            ?: throw IOException("BibleHub Text: empty response body for $book $chapter")

        val doc = Jsoup.parse(body)
        val paragraphs = doc.select("div.chapter p")

        var currentVerse = 0
        paragraphs.forEach { p ->
            val verseLink = p.selectFirst("a[href*='.htm']")
            val verseSup = p.selectFirst("sup")

            val verseText = when {
                verseLink != null -> {
                    val num = verseLink.text().filter { it.isDigit() }.toIntOrNull()
                    if (num != null) currentVerse = num
                    verseLink.remove()
                    p.text().trim()
                }
                verseSup != null -> {
                    val num = verseSup.text().filter { it.isDigit() }.toIntOrNull()
                    if (num != null) currentVerse = num
                    verseSup.remove()
                    p.text().trim()
                }
                else -> p.text().trim()
            }

            if (currentVerse > 0 && verseText.isNotEmpty()) {
                onVerse(currentVerse, verseText)
            }
        }
    }

    override fun getBaseUrl(): String = "biblehub.com"

    override fun getPriority(): Int = 50 // Secondary priority

    /**
     * BibleHub text pages support most books.
     */
    override fun supportsBook(book: String): Boolean = true

    private fun interlinearSlug(book: String): String {
        val normalized = book.lowercase().replace(" ", "")
        return when (normalized) {
            "songofsolomon", "songofsongs", "songofsong" -> "songs"
            else -> normalized.replace(Regex("^(\\d+)([a-z]+)$")) { m ->
                "${m.groupValues[1]}_${m.groupValues[2]}"
            }
        }
    }
}