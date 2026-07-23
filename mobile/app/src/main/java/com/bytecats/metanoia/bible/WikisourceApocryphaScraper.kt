package com.bytecats.metanoia.bible

import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException

/**
 * Scrapes the King James Version Apocrypha text of four deuterocanonical
 * Old Testament books — Tobit, Judith, Wisdom, Sirach — from Wikisource's
 * "Bible (King James)" edition (https://en.wikisource.org/wiki/Bible_(King_James)).
 *
 * Why this exists: these four books have no page on BibleGateway, so
 * BibleScraper.scrapeChapter can never source them (see
 * docs/MAINTENANCE.md's "Deuterocanonical/Ethiopian" note and
 * src/bible_db.zig's `books_with_no_verse_text`, which documents this as a
 * known upstream gap, not a porting gap). This is new scraping logic
 * against a different, real, verified source — nothing to "port" here.
 *
 * Source verification performed during development (2026-07-22): fetched
 * the real Wikisource pages for all four books directly and confirmed (a)
 * they contain the actual KJV Apocrypha verse text with one
 * `<span class="wst-verse">` marker per verse, always as the first child of
 * its own `<p>` (spot-checked: 244/244 Tobit verses, 339/339 Judith,
 * 436/436 Wisdom, 1392/1392 Sirach each had exactly one verse span per
 * paragraph — no paragraph held more than one verse), and (b) the chapter
 * counts found (14/16/19/51) exactly match this app's BibleConstants.kt
 * BOOKS list for these books.
 *
 * sacred-texts.com — the more obvious candidate for this kind of
 * public-domain text — was investigated and rejected: as of this writing
 * its entire domain sits behind a Cloudflare JS challenge (`cf-mitigated:
 * challenge` response header, HTTP 403 for curl and for an OkHttp-style
 * request regardless of User-Agent string, including a real Android/Chrome
 * UA). An OkHttp scraper can never pass a JS challenge since it can't
 * execute JavaScript, so that domain is not viable for this codebase no
 * matter how good its content is. Wikisource has no such protection.
 */
class WikisourceApocryphaScraper(
    // Same rationale as BibleScraper: typed as the Call.Factory interface so
    // tests can substitute a fake without a real HTTP stack.
    private val client: Call.Factory = OkHttpClient(),
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro)"
) {
    companion object {
        // Canonical book name (as used throughout this app — see
        // models/BibleConstants.kt's BOOKS) -> Wikisource page slug under
        // "Bible_(King_James)/". Sirach is catalogued there under its KJV
        // Apocrypha name, Ecclesiasticus; Wisdom is "Wisdom_of_Solomon".
        private val BOOK_SLUGS = mapOf(
            "Tobit" to "Tobit",
            "Judith" to "Judith",
            "Wisdom" to "Wisdom_of_Solomon",
            "Sirach" to "Ecclesiasticus"
        )

        /** Books this scraper can actually source. Check membership before calling scrapeChapter. */
        val SUPPORTED_BOOKS: Set<String> = BOOK_SLUGS.keys
    }

    // NOTE: like BibleScraper, this does not catch-and-swallow its own
    // network/parse exceptions — they propagate so BibleManager can
    // distinguish "failed" from "still loading" (see BibleScraper.kt's
    // top-of-file note for the bug class this avoids).
    suspend fun scrapeChapter(
        book: String, chapter: Int,
        onVerse: (Int, String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val slug = BOOK_SLUGS[book]
            ?: throw IllegalArgumentException("WikisourceApocryphaScraper does not support book '$book'")
        val url = "https://en.wikisource.org/wiki/Bible_(King_James)/$slug"
        val request = Request.Builder().url(url).header("User-Agent", userAgent).build()
        val response = client.newCall(request).execute()
        val body = response.body?.string()
            ?: throw IOException("scrapeChapter: empty response body for $book $chapter (Wikisource)")
        val doc = Jsoup.parse(body)
        val prefix = "$chapter:"
        doc.select("p:has(span.wst-verse)").forEach { p ->
            val span = p.selectFirst("span.wst-verse") ?: return@forEach
            val id = span.id() // e.g. "3:14" (chapter:verse)
            if (!id.startsWith(prefix)) return@forEach
            val verseNum = id.substringAfter(':').toIntOrNull() ?: return@forEach
            // The verse's superscript number is rendered as plain text inside
            // the paragraph (e.g. "14 And it came to pass..."); strip the
            // leading number so onVerse gets prose text only.
            val supText = span.selectFirst("sup")?.text() ?: ""
            val text = p.text().removePrefix(supText).trim()
            if (text.isNotEmpty()) onVerse(verseNum, text)
        }
    }
}
