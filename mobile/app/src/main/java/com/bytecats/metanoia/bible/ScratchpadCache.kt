package com.bytecats.metanoia.bible

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jsoup.Jsoup
import java.io.File

/**
 * Local cache for scraped HTML content.
 *
 * Stores raw HTML on device storage so scrapers can work offline
 * and avoid hitting real endpoints repeatedly.
 */
class ScratchpadCache(private val context: Context) {
    private val cacheDir = File(context.filesDir, "bible_scraper_cache")

    init {
        cacheDir.mkdirs()
    }

    /**
     * Get cached HTML for a scraper request.
     */
    fun getCacheKey(scraper: String, book: String, chapter: Int, version: String): String {
        return "${scraper}_${book}_${chapter}_${version}"
    }

    /**
     * Load cached HTML from local storage.
     */
    fun getCachedHtml(scraper: String, book: String, chapter: Int, version: String): String? {
        val key = getCacheKey(scraper, book, chapter, version)
        val file = File(cacheDir, "$key.html")

        return if (file.exists()) {
            file.readText()
        } else {
            null
        }
    }

    /**
     * Cache HTML for offline/future use.
     */
    fun cacheHtml(scraper: String, book: String, chapter: Int, version: String, html: String) {
        val key = getCacheKey(scraper, book, chapter, version)
        val file = File(cacheDir, "$key.html")

        try {
            file.writeText(html)
        } catch (e: Exception) {
            // Cache writes shouldn't fail the app
            e.printStackTrace()
        }
    }

    /**
     * Check if cached content exists and is valid (not empty).
     */
    fun hasValidCache(scraper: String, book: String, chapter: Int, version: String): Boolean {
        val cached = getCachedHtml(scraper, book, chapter, version)
        return !cached.isNullOrEmpty()
    }

    /**
     * Clear all cached content (useful for testing or force-refresh).
     */
    fun clearCache() {
        cacheDir.listFiles()?.forEach { it.delete() }
    }

    /**
     * Get cache size in bytes.
     */
    fun getCacheSize(): Long {
        return cacheDir.walkTopDown().filter { it.isFile }.map { it.length() }.sum()
    }
}

/**
 * Mock scraper that uses cached HTML instead of real network requests.
 *
 * Useful for:
 * - Testing scraper logic without hitting real endpoints
 * - Offline reading when cached content exists
 * - Avoiding rate limits during development
 */
class CachedChapterScraper(
    private val cache: ScratchpadCache,
    private val realScraper: ChapterScraper
) : ChapterScraper {

    companion object {
        // Enable/disable cached mode
        var useCache = true
    }

    override suspend fun scrapeChapter(
        book: String, chapter: Int, version: String,
        onVerse: (Int, String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val scraperName = realScraper.getBaseUrl().replace(".", "_")

        if (useCache && cache.hasValidCache(scraperName, book, chapter, version)) {
            // Use cached HTML
            val cachedHtml = cache.getCachedHtml(scraperName, book, chapter, version)!!
            parseAndCall(cachedHtml, book, chapter, version, onVerse)
        } else {
            // Fetch from real source and cache it
            realScraper.scrapeChapter(book, chapter, version) { verseNum, text ->
                // We can't cache parsed data because we don't have the raw HTML
                // So this cached scraper only works if pre-cached
                onVerse(verseNum, text)
            }
        }
    }

    override fun getBaseUrl(): String = realScraper.getBaseUrl()

    override fun getPriority(): Int = realScraper.getPriority()

    override fun supportsBook(book: String): Boolean = realScraper.supportsBook(book)

    /**
     * Parse cached HTML and extract verses (logic depends on scraper type).
     */
    private fun parseAndCall(
        html: String,
        book: String,
        chapter: Int,
        version: String,
        onVerse: (Int, String) -> Unit
    ) {
        val doc = Jsoup.parse(html)

        when (realScraper) {
            is BibleGatewayScraper -> {
                doc.select("h1, h2, h3, h4, h5, h6").remove()
                doc.select("div.passage-text span.text").forEach { span ->
                    val className = span.className()
                    val verseNum = Regex("-(\\d+)$").find(className)?.groupValues?.get(1)?.toInt()

                    if (verseNum != null) {
                        span.select("sup, span.chapternum, span.versenum").remove()
                        onVerse(verseNum, span.text().trim())
                    }
                }
            }
            is BibleHubTextScraper -> {
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
            else -> {
                // Fallback: try to extract any pattern that looks like verses
                // This won't work well, but at least won't crash
                doc.select("span").forEach { span ->
                    val text = span.text().trim()
                    val verseMatch = Regex("^\\d+\\s+(.+)").find(text)
                    if (verseMatch != null) {
                        val verseNum = Regex("^\\d+").find(text)?.value?.toIntOrNull()
                        val verseText = verseMatch.groupValues[1]
                        if (verseNum != null && verseText.isNotEmpty()) {
                            onVerse(verseNum, verseText)
                        }
                    }
                }
            }
        }
    }
}