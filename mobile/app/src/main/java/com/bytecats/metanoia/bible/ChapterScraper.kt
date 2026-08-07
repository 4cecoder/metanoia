package com.bytecats.metanoia.bible

import java.io.IOException

/**
 * Base interface for Bible chapter scrapers.
 *
 * All scrapers implement this interface, making them interchangeable
 * and easy to mock/delegate during testing.
 */
interface ChapterScraper {
    /**
     * Scrape a chapter and call onVerse for each verse found.
     *
     * @param book Book name (e.g., "Genesis", "Psalms", "Matthew")
     * @param chapter Chapter number (1-based)
     * @param version Translation/version identifier
     * @param onVerse Callback called for each verse: (verseNumber, verseText)
     *
     * @throws IOException on network/parse failures
     */
    suspend fun scrapeChapter(
        book: String,
        chapter: Int,
        version: String,
        onVerse: (Int, String) -> Unit
    )

    /**
     * Return the base URL for this scraper (for rate limiting).
     */
    fun getBaseUrl(): String

    /**
     * Check if this scraper supports the given book.
     */
    fun supportsBook(book: String): Boolean = true

    /**
     * Get the scraper's priority (lower = higher priority).
     */
    fun getPriority(): Int = 100
}