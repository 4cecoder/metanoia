package com.bytecats.metanoia.bible

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.TimeSource
import kotlin.time.Duration.Companion.seconds

/**
 * Robust chapter fetching with multiple source fallback and rate limiting.
 *
 * Implements:
 * - Multiple source attempts (BibleGateway → BibleHub)
 * - Rate limiting to avoid server bans
 * - Exponential backoff on failures
 * - Request deduplication (don't fetch same chapter twice in rapid succession)
 */
class RobustChapterFetcher(
    private val bibleGateway: BibleScraper = BibleScraper(),
    private val bibleHub: BibleHubScraper = BibleHubScraper(),
    private val wikisourceApocrypha: WikisourceApocryphaScraper = WikisourceApocryphaScraper()
) {
    companion object {
        // Minimum delay between requests to any domain
        private const val MIN_REQUEST_DELAY_MS = 1000L

        // Maximum backoff delay
        private const val MAX_BACKOFF_MS = 10000L

        // Last request timestamp per domain
        private val lastRequestTime = mutableMapOf<String, TimeSource.Monotonic.ValueTimeMark>()

        // In-flight request cache (deduplication)
        private val inFlightRequests = mutableMapOf<String, suspend () -> Unit>()
    }

    /**
     * Rate limiter - ensures minimum delay between requests to each domain.
     */
    private suspend fun rateLimit(domain: String) {
        val now = TimeSource.Monotonic.markNow()
        val lastTime = lastRequestTime[domain]

        if (lastTime != null) {
            val elapsed = now - lastTime
            val remainingDelay = MIN_REQUEST_DELAY_MS.milliseconds - elapsed
            if (remainingDelay > Duration.ZERO) {
                delay(remainingDelay)
            }
        }

        lastRequestTime[domain] = TimeSource.Monotonic.markNow()
    }

    /**
     * Deduplicate concurrent requests for the same chapter.
     * If the same chapter is requested while already in flight,
     * return the existing in-flight request instead of starting a new one.
     */
    private fun <T> deduplicate(key: String, block: suspend () -> T): suspend () -> T {
        synchronized(inFlightRequests) {
            @Suppress("UNCHECKED_CAST")
            val existing = inFlightRequests[key] as? suspend () -> T
            if (existing != null) {
                return existing
            }

            val newBlock: suspend () -> T = {
                try {
                    block()
                } finally {
                    synchronized(inFlightRequests) {
                        inFlightRequests.remove(key)
                    }
                }
            }

            inFlightRequests[key] = newBlock as suspend () -> Unit
            return newBlock
        }
    }

    /**
     * Fetch a chapter with source fallback and retry logic.
     *
     * Strategy:
     * 1. Try primary source (BibleGateway for most, Wikisource for apocrypha)
     * 2. On failure, try secondary source (BibleHub)
     * 3. Exponential backoff between retries
     */
    suspend fun fetchChapter(
        book: String,
        chapter: Int,
        version: String = "NKJV",
        onVerse: (Int, String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val cacheKey = "${book}_${chapter}_${version}"

        deduplicate(cacheKey) {
            var lastError: Exception? = null

            // Determine primary source based on book type
            val isApocrypha = book in WikisourceApocryphaScraper.SUPPORTED_BOOKS

            if (isApocrypha) {
                // Apocrypha: Try Wikisource first, then BibleHub
                tryWithBackoff("Wikisource", "en.wikisource.org") {
                    rateLimit("en.wikisource.org")
                    wikisourceApocrypha.scrapeChapter(book, chapter, onVerse)
                } ?: tryWithBackoff("BibleHub", "biblehub.com") {
                    rateLimit("biblehub.com")
                    bibleHub.scrapeChapter(book, chapter, "kjv", onVerse)
                } ?: throw lastError ?: IOException("All sources failed for $book $chapter")
            } else {
                // Standard books: Try BibleGateway first, then BibleHub
                tryWithBackoff("BibleGateway", "www.biblegateway.com") {
                    rateLimit("www.biblegateway.com")
                    bibleGateway.scrapeChapter(book, chapter, version, onVerse)
                } ?: tryWithBackoff("BibleHub", "biblehub.com") {
                    rateLimit("biblehub.com")
                    bibleHub.scrapeChapter(book, chapter, version.lowercase(), onVerse)
                } ?: throw lastError ?: IOException("All sources failed for $book $chapter")
            }
        }()
    }

    /**
     * Try an operation with exponential backoff.
     * Returns null if all retries fail, otherwise returns Unit.
     */
    private suspend fun tryWithBackoff(
        sourceName: String,
        domain: String,
        maxRetries: Int = 3,
        operation: suspend () -> Unit
    ): Unit? {
        var backoffMs = 500L // Initial backoff

        repeat(maxRetries) { attempt ->
            try {
                operation()
                return Unit // Success
            } catch (e: Exception) {
                // Log the failure
                e.printStackTrace()

                if (attempt < maxRetries - 1) {
                    // Backoff before retry
                    delay(backoffMs)
                    backoffMs = (backoffMs * 2).coerceAtMost(MAX_BACKOFF_MS)
                } else {
                    // Last attempt failed
                    throw IOException("$sourceName failed after $maxRetries attempts: ${e.message}", e)
                }
            }
        }
        return null
    }
}