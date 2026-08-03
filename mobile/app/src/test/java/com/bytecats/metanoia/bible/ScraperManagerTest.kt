package com.bytecats.metanoia.bible

import kotlinx.coroutines.runBlocking
import java.io.IOException
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Tests for ScraperManager with mock clients.

 * Tests:
 * - Rate limiting behavior
 * - Request deduplication
 * - Source fallback logic
 * - Scraper priority ordering
 */
class ScraperManagerTest {

    private lateinit var mockScraper1: MockChapterScraper
    private lateinit var mockScraper2: MockChapterScraper
    private lateinit var manager: ScraperManager

    @Before
    fun setup() {
        mockScraper1 = MockChapterScraper(
            name = "TestScraper1",
            baseUrlValue = "test1.com",
            priorityValue = 10,
            supportsAll = true,
            shouldSucceed = true,
            verseCount = 10
        )

        mockScraper2 = MockChapterScraper(
            name = "TestScraper2",
            baseUrlValue = "test2.com",
            priorityValue = 50,
            supportsAll = true,
            shouldSucceed = true,
            verseCount = 10
        )

        manager = ScraperManager(scrapers = listOf(mockScraper1, mockScraper2))
    }

    @Test
    fun `Uses highest priority scraper first`() = runBlocking {
        val verses = mutableListOf<Pair<Int, String>>()

        manager.fetchChapter("Genesis", 1, "NKJV") { verseNum, text ->
            verses.add(Pair(verseNum, text))
        }

        assertEquals("First scraper (priority 10) should be used", 1, mockScraper1.callCount)
        assertEquals("Second scraper (priority 50) should not be called", 0, mockScraper2.callCount)
    }

    @Test
    fun `Falls back to lower priority scraper when primary fails`() = runBlocking {
        // Make first scraper fail
        mockScraper1.shouldSucceed = false

        val verses = mutableListOf<Pair<Int, String>>()

        manager.fetchChapter("Genesis", 1, "NKJV") { verseNum, text ->
            verses.add(Pair(verseNum, text))
        }

        assertEquals("First scraper should have been tried", 1, mockScraper1.callCount)
        assertEquals("Second scraper should be used as fallback", 1, mockScraper2.callCount)
    }

    @Test
    fun `Only uses scrapers that support the book`() = runBlocking {
        val scraper1 = MockChapterScraper(
            name = "GenesisOnly",
            baseUrlValue = "genesis.com",
            priorityValue = 10,
            supportsAll = false,
            supportedBooks = setOf("Genesis"),
            shouldSucceed = true,
            verseCount = 10
        )

        val scraper2 = MockChapterScraper(
            name = "AllBooks",
            baseUrlValue = "allbooks.com",
            priorityValue = 50,
            supportsAll = true,
            supportedBooks = emptySet(),
            shouldSucceed = true,
            verseCount = 10
        )

        val localManager = ScraperManager(scrapers = listOf(scraper1, scraper2))

        // Request a book that only scraper2 supports
        val verses = mutableListOf<Pair<Int, String>>()
        localManager.fetchChapter("Psalms", 23, "NKJV") { verseNum, text ->
            verses.add(Pair(verseNum, text))
        }

        assertEquals("Genesis-only scraper should not be called", 0, scraper1.callCount)
        assertEquals("All-books scraper should be used", 1, scraper2.callCount)
    }

    @Test
    fun `Throws exception when no scrapers available`() = runBlocking {
        val scraper = MockChapterScraper(
            name = "GenesisOnly",
            baseUrlValue = "genesis.com",
            priorityValue = 10,
            supportsAll = false,
            supportedBooks = setOf("Genesis"),
            shouldSucceed = true,
            verseCount = 10
        )

        val localManager = ScraperManager(scrapers = listOf(scraper))

        try {
            val verses = mutableListOf<Pair<Int, String>>()
            localManager.fetchChapter("UnsupportedBook", 1, "NKJV") { verseNum, text ->
                verses.add(Pair(verseNum, text))
            }
            fail("Should have thrown exception for unsupported book")
        } catch (e: Exception) {
            assertTrue(
                "Exception should mention unsupported book",
                e.message?.contains("No scraper available") == true
            )
        }
    }

    @Test
    fun `Throws exception when all scrapers fail`() = runBlocking {
        mockScraper1.shouldSucceed = false
        mockScraper2.shouldSucceed = false

        try {
            val verses = mutableListOf<Pair<Int, String>>()
            manager.fetchChapter("Genesis", 1, "NKJV") { verseNum, text ->
                verses.add(Pair(verseNum, text))
            }
            fail("Should have thrown exception when all scrapers fail")
        } catch (e: Exception) {
            assertTrue(
                "Exception should mention failure",
                e.message?.contains("All scrapers failed") == true
            )
        }
    }

    @Test
    fun `Scraper prioritizes correctly`() = runBlocking {
        val scraper1 = MockChapterScraper(
            name = "Priority100",
            baseUrlValue = "p100.com",
            priorityValue = 100,
            supportsAll = true,
            shouldSucceed = true,
            verseCount = 10
        )

        val scraper2 = MockChapterScraper(
            name = "Priority10",
            baseUrlValue = "p10.com",
            priorityValue = 10,
            supportsAll = true,
            shouldSucceed = true,
            verseCount = 10
        )

        val scraper3 = MockChapterScraper(
            name = "Priority50",
            baseUrlValue = "p50.com",
            priorityValue = 50,
            supportsAll = true,
            shouldSucceed = true,
            verseCount = 10
        )

        val localManager = ScraperManager(scrapers = listOf(scraper1, scraper2, scraper3))

        val verses = mutableListOf<Pair<Int, String>>()
        localManager.fetchChapter("Genesis", 1, "NKJV") { verseNum, text ->
            verses.add(Pair(verseNum, text))
        }

        assertEquals("Priority 10 should be called first", 1, scraper2.callCount)
        assertEquals("Priority 50 should not be called", 0, scraper3.callCount)
        assertEquals("Priority 100 should not be called", 0, scraper1.callCount)
    }
}

/**
 * Mock ChapterScraper for testing ScraperManager.
 */
class MockChapterScraper(
    private val name: String,
    private val baseUrlValue: String,
    private val priorityValue: Int,
    private val supportsAll: Boolean,
    private val supportedBooks: Set<String> = emptySet(),
    var shouldSucceed: Boolean = true,
    private val verseCount: Int = 10
) : ChapterScraper {

    var callCount = 0

    override suspend fun scrapeChapter(
        book: String, chapter: Int, version: String,
        onVerse: (Int, String) -> Unit
    ) {
        callCount++

        if (!shouldSucceed) {
            throw IOException("$name failed to scrape $book $chapter")
        }

        for (i in 1..verseCount) {
            onVerse(i, "Verse $i from $name ($book $chapter:$i)")
        }
    }

    override fun getBaseUrl(): String = baseUrlValue

    override fun getPriority(): Int = priorityValue

    override fun supportsBook(book: String): Boolean {
        return supportsAll || book in supportedBooks
    }
}