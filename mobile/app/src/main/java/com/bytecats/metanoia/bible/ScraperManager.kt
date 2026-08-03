package com.bytecats.metanoia.bible

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.TimeSource
import java.io.IOException

/**
 * Rate-limited scraper manager with intelligent source selection.
 *
 * Features:
 * - Per-domain rate limiting (configurable delays)
 * - Request deduplication (don't fetch same chapter twice concurrently)
 * - Source prioritization (try best sources first)
 * - Fallback to alternative sources on failure
 * - Exponential backoff on transient failures
 */
class ScraperManager(
    private val scrapers: List<ChapterScraper> = listOf(
        BibleGatewayScraper(),
        BibleHubTextScraper()
    ),
    private val cache: ScratchpadCache? = null
) {
    companion object {
        // Rate limiting: minimum delay between requests per domain
        private const val DEFAULT_MIN_REQUEST_DELAY_MS = 1000L

        // Maximum backoff delay
        private const val MAX_BACKOFF_MS = 10000L

        // In-flight request deduplication cache
        private val inFlightRequests = mutableMapOf<String, suspend () -> Unit>()
    }

    private val rateLimiter = RateLimiter(DEFAULT_MIN_REQUEST_DELAY_MS)

    /**
     * Rate limiter with per-domain tracking.
     */
    private class RateLimiter(
        private val minDelayMs: Long
    ) {
        private val lastRequestTime = mutableMapOf<String, TimeSource.Monotonic.ValueTimeMark>()

        suspend fun waitForSlot(domain: String) {
            val now = TimeSource.Monotonic.markNow()
            val lastTime = lastRequestTime[domain]

            if (lastTime != null) {
                val elapsed = now - lastTime
                val remainingDelay = minDelayMs.milliseconds - elapsed
                if (remainingDelay > Duration.ZERO) {
                    delay(remainingDelay)
                }
            }

            lastRequestTime[domain] = TimeSource.Monotonic.markNow()
        }

        fun clear() {
            lastRequestTime.clear()
        }
    }

    /**
     * Deduplicate concurrent requests for the same chapter.
     * Returns the existing in-flight request if available, otherwise creates a new one.
     */
    private fun deduplicate(key: String, block: suspend () -> Unit): suspend () -> Unit {
        synchronized(inFlightRequests) {
            val existing = inFlightRequests[key]
            if (existing != null) {
                return existing
            }

            val newBlock: suspend () -> Unit = {
                try {
                    block()
                } finally {
                    synchronized(inFlightRequests) {
                        inFlightRequests.remove(key)
                    }
                }
            }

            inFlightRequests[key] = newBlock
            return newBlock
        }
    }

    /**
     * Fetch a chapter using the best available scraper with rate limiting and fallback.
     *
     * Strategy:
     * 1. Check for in-flight request (deduplication)
     * 2. Try scrapers in priority order
     * 3. Rate limit per domain
     * 4. Fallback to next scraper on failure
     * 5. Exponential backoff between retries
     */
    suspend fun fetchChapter(
        book: String,
        chapter: Int,
        version: String,
        onVerse: (Int, String) -> Unit
    ) = withContext(Dispatchers.IO) {
        val cacheKey = "${book}_${chapter}_${version}"

        deduplicate(cacheKey) {
            // Sort scrapers by priority (lower = higher priority)
            val sortedScrapers = scrapers
                .filter { it.supportsBook(book) }
                .sortedBy { it.getPriority() }

            if (sortedScrapers.isEmpty()) {
                throw IOException("No scraper available for book: $book")
            }

            var lastError: Exception? = null
            var success = false

            for (scraper in sortedScrapers) {
                if (success) break

                try {
                    // Rate limit this domain
                    rateLimiter.waitForSlot(scraper.getBaseUrl())

                    // Try to fetch with exponential backoff
                    tryWithBackoff(scraper.getBaseUrl()) {
                        scraper.scrapeChapter(book, chapter, version, onVerse)
                        success = true
                    }
                } catch (e: Exception) {
                    lastError = e
                    // Try next scraper
                    continue
                }
            }

            if (!success) {
                // All scrapers failed
                throw IOException(
                    "All scrapers failed for $book $chapter ($version). " +
                    "Scrapers tried: ${sortedScrapers.joinToString { it.getBaseUrl() }}",
                    lastError
                )
            }
        }()
    }

    /**
     * Retry an operation with exponential backoff.
     */
    private suspend fun tryWithBackoff(
        sourceName: String,
        maxRetries: Int = 3,
        operation: suspend () -> Unit
    ) {
        var backoffMs = 500L // Initial backoff

        repeat(maxRetries) { attempt ->
            try {
                operation()
                return // Success
            } catch (e: Exception) {
                if (attempt < maxRetries - 1) {
                    delay(backoffMs)
                    backoffMs = (backoffMs * 2).coerceAtMost(MAX_BACKOFF_MS)
                } else {
                    throw IOException("$sourceName failed after $maxRetries attempts: ${e.message}", e)
                }
            }
        }
    }

    /**
     * Get statistics about in-flight requests.
     */
    fun getInFlightCount(): Int {
        synchronized(inFlightRequests) {
            return inFlightRequests.size
        }
    }

    /**
     * Clear rate limiter state (useful for testing).
     */
    fun clearRateLimiter() {
        rateLimiter.clear()
    }
}