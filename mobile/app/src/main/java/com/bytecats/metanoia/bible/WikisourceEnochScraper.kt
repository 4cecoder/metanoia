package com.bytecats.metanoia.bible

import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException

/**
 * Scrapes R.H. Charles' 1917 public-domain English translation of the Book
 * of Enoch from Wikisource, one page per chapter:
 * https://en.wikisource.org/wiki/The_Book_of_Enoch_(Charles)/Chapter_NN
 *
 * Why this exists: Enoch has no BibleGateway page (see
 * docs/MAINTENANCE.md / src/bible_db.zig's `books_with_no_verse_text`), so
 * BibleScraper can't source it. sacred-texts.com hosts the same Charles
 * translation (verified live in a real browser at sacred-texts.com/bib/boe/
 * during research) but was rejected as a source: its entire domain now sits
 * behind a Cloudflare JS challenge that returns HTTP 403 to any non-browser
 * client (confirmed with curl using several User-Agent strings, including a
 * real Android/Chrome one) — unreachable from OkHttp/Jsoup no matter how
 * good the content is. Wikisource has the same translation, unprotected,
 * split one chapter per page (confirmed 108 chapter pages, Chapter_01
 * through Chapter_108, matching this app's BibleConstants.kt chapter count
 * for Enoch exactly).
 *
 * Unlike the four books in WikisourceApocryphaScraper, this edition does
 * *not* tag verses with dedicated HTML markup — verse numbers are plain
 * inline text ("1. In the beginning... 2. And then..."), several verses
 * per `<p>`, with poetic lines sometimes split across additional `<p>` tags
 * that don't start a new verse. This is parsed by joining all paragraph
 * text in the chapter and splitting on the "<number>. " markers.
 *
 * This heuristic was checked against real fetched pages spanning very
 * different content, notably the numbers-dense calendrical chapter 72
 * ("Book of the Heavenly Luminaries") — Charles' translation always spells
 * out in-prose numbers as words ("ten parts", "sixty times", "three
 * hundred and sixty-four"), never as bare digits, so a bare "<digits>. "
 * sequence should only ever be a genuine verse marker in this text. Still,
 * this is inherently more fragile than tag-based parsing (WikisourceEnochScraperTest
 * documents the exact fixture this was validated against) — a future
 * upstream edit that inlines a footnote number differently could break it.
 */
class WikisourceEnochScraper(
    private val client: Call.Factory = OkHttpClient(),
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro)"
) {
    companion object {
        const val BOOK_NAME = "Enoch"
        private val VERSE_MARKER = Regex("(?:^|\\s)(\\d{1,3})\\.\\s+")
    }

    // NOTE: does not catch-and-swallow its own network/parse exceptions —
    // see BibleScraper.kt's top-of-file note for the bug class this avoids.
    suspend fun scrapeChapter(
        chapter: Int,
        onVerse: (Int, String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val padded = chapter.toString().padStart(2, '0')
        val url = "https://en.wikisource.org/wiki/The_Book_of_Enoch_(Charles)/Chapter_$padded"
        val request = Request.Builder().url(url).header("User-Agent", userAgent).build()
        val response = client.newCall(request).execute()
        val body = response.body?.string()
            ?: throw IOException("scrapeChapter: empty response body for Enoch $chapter")
        val doc = Jsoup.parse(body)
        val fullText = doc.select("div#mw-content-text p").joinToString(" ") { it.text() }

        val matches = VERSE_MARKER.findAll(fullText).toList()
        for (i in matches.indices) {
            val m = matches[i]
            val verseNum = m.groupValues[1].toIntOrNull() ?: continue
            val textStart = m.range.last + 1
            val textEnd = if (i + 1 < matches.size) matches[i + 1].range.first else fullText.length
            if (textStart >= textEnd) continue
            val text = fullText.substring(textStart, textEnd).trim()
            if (text.isNotEmpty()) onVerse(verseNum, text)
        }
    }
}
