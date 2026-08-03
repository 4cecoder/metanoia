package com.bytecats.metanoia.bible

import com.bytecats.metanoia.models.strongsLanguagePrefix
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import java.io.IOException

/**
 * BibleHub scraper - secondary source for verse text.
 *
 * BibleHub provides chapter content at URLs like:
 * https://biblehub.com/text/genesis/1.htm
 *
 * Used as a fallback when BibleGateway fails or is rate-limited.
 */
class BibleHubScraper(
    private val client: Call.Factory = OkHttpClient(),
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro)"
) {
    suspend fun scrapeChapter(
        book: String, chapter: Int, version: String = "kjv",
        onVerse: (Int, String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val bookSlug = interlinearSlug(book)
        val url = "https://biblehub.com/text/$bookSlug/$chapter.htm"
        val request = Request.Builder().url(url).header("User-Agent", userAgent).build()
        val response = client.newCall(request).execute()

        if (!response.isSuccessful) {
            throw IOException("BibleHub: HTTP ${response.code} for $book $chapter ($url)")
        }

        val body = response.body?.string()
            ?: throw IOException("BibleHub: empty response body for $book $chapter")

        val doc = Jsoup.parse(body)

        // BibleHub text pages have <p> tags with verse content
        // Each verse starts with <a href="...">1</a> or <sup>1</sup>
        val paragraphs = doc.select("div.chapter p")

        var currentVerse = 0
        paragraphs.forEach { p ->
            // Look for verse markers at the start of the paragraph
            val verseLink = p.selectFirst("a[href*='.htm']")
            val verseSup = p.selectFirst("sup")

            val verseText = if (verseLink != null) {
                val num = verseLink.text().filter { it.isDigit() }.toIntOrNull()
                if (num != null) currentVerse = num
                verseLink.remove()
                p.text().trim()
            } else if (verseSup != null) {
                val num = verseSup.text().filter { it.isDigit() }.toIntOrNull()
                if (num != null) currentVerse = num
                verseSup.remove()
                p.text().trim()
            } else {
                // Continuation of previous verse
                p.text().trim()
            }

            if (currentVerse > 0 && verseText.isNotEmpty()) {
                onVerse(currentVerse, verseText)
            }
        }
    }

    /**
     * BibleHub URLs use the same slug format as interlinear pages.
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
}