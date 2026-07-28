package com.bytecats.metanoia.bible

import com.bytecats.metanoia.bible.BibleCacheManager
import com.bytecats.metanoia.bible.BibleManager
import com.bytecats.metanoia.models.BibleBook
import com.bytecats.metanoia.models.BOOKS
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Tests for Bible caching behavior to prevent overwhelming external endpoints.
 *
 * Key principles:
 * 1. Check cache before fetching (cache-first)
 * 2. Don't refetch if cache is valid
 * 3. Batch prefetch should be idempotent
 * 4. Error recovery should not trigger retry storms
 */
class BibleCachingBehaviorTest {
    private lateinit var mockBibleManager: MockBibleManager
    private lateinit var cacheManager: BibleCacheManager

    @Before
    fun setup() {
        mockBibleManager = MockBibleManager()
        cacheManager = BibleCacheManager(
            context = MockContext(),
            bibleManager = mockBibleManager,
            settings = MockSettingsManager()
        )
    }

    @Test
    fun ensureChapterDoesNotRefetchWhenCacheIsValid() {
        // Setup: Genesis 1 is already cached
        mockBibleManager.setCachedChapter("Genesis", 1, listOf(1 to "In the beginning God"))

        // Act: Ensure chapter (should use cache, not fetch)
        val result = runBlocking {
            cacheManager.ensureChapter("Genesis", 1)
        }

        // Assert: Should return true (has content) and NOT trigger fetch
        assertTrue("Should have content from cache", result)
        assertEquals("Should not fetch when cache is valid", 0, mockBibleManager.fetchChapterCallCount)
    }

    @Test
    fun ensureChapterFetchesOnlyWhenCacheIsEmpty() {
        // Setup: Genesis 1 is NOT cached
        mockBibleManager.setCachedChapter("Genesis", 1, emptyList())

        // Act: Ensure chapter (should fetch)
        val result = runBlocking {
            cacheManager.ensureChapter("Genesis", 1)
        }

        // Assert: Should return true (has content after fetch) and trigger ONE fetch
        assertTrue("Should have content after fetch", result)
        assertEquals("Should fetch exactly once when cache is empty", 1, mockBibleManager.fetchChapterCallCount)
    }

    @Test
    fun prefetchBookDoesNotRefetchCachedChapters() {
        // Setup: Genesis chapters 1-5 are cached, 6-10 are not
        (1..5).forEach { ch ->
            mockBibleManager.setCachedChapter("Genesis", ch, listOf(ch to "Verse $ch"))
        }

        // Act: Prefetch entire Genesis (50 chapters)
        runBlocking {
            cacheManager.prefetchBook(BibleBook("Genesis", 50, "Old"))
        }

        // Assert: Should only fetch chapters 6-50 (45 fetches), not 1-5
        assertEquals("Should only fetch uncached chapters", 45, mockBibleManager.fetchChapterCallCount)
    }

    @Test
    fun prefetchBookIsIdempotent() {
        // Setup: No chapters cached

        // Act: Prefetch Genesis twice
        runBlocking {
            cacheManager.prefetchBook(BibleBook("Genesis", 50, "Old"))
        }
        val firstFetchCount = mockBibleManager.fetchChapterCallCount

        runBlocking {
            cacheManager.prefetchBook(BibleBook("Genesis", 50, "Old"))
        }
        val secondFetchCount = mockBibleManager.fetchChapterCallCount

        // Assert: Second prefetch should not refetch anything (all cached now)
        assertEquals("First prefetch should fetch all 50 chapters", 50, firstFetchCount)
        assertEquals("Second prefetch should fetch nothing (all cached)", 50, secondFetchCount)
    }

    @Test
    fun ensureChapterReturnsFalseOnFetchFailure() {
        // Setup: Genesis 1 is NOT cached and fetch will fail
        mockBibleManager.setCachedChapter("Genesis", 1, emptyList())
        mockBibleManager.setFetchShouldFail(true)

        // Act: Ensure chapter (should try to fetch and fail)
        val result = runBlocking {
            cacheManager.ensureChapter("Genesis", 1)
        }

        // Assert: Should return false (no content) and trigger ONE fetch attempt
        assertFalse("Should return false when fetch fails", result)
        assertEquals("Should attempt fetch exactly once", 1, mockBibleManager.fetchChapterCallCount)
    }

    @Test
    fun prefetchBookContinuesAfterSingleChapterFailure() {
        // Setup: Genesis 3 will fail, others succeed
        mockBibleManager.setFetchShouldFailForChapters(setOf(3))

        // Act: Prefetch Genesis chapters 1-5
        runBlocking {
            cacheManager.prefetchBook(BibleBook("Genesis", 5, "Old"))
        }

        // Assert: Should attempt all 5 chapters, with 4 successes
        assertEquals("Should attempt all chapters", 5, mockBibleManager.fetchChapterCallCount)
        assertEquals("Should report failure for chapter 3", "Failed at chapter 3",
            cacheManager.prefetchErrors.value["Genesis"])
    }

    @Test
    fun isBookCachedReturnsTrueWhenAllChaptersPresent() {
        // Setup: All Psalms chapters (150) are cached
        (1..150).forEach { ch ->
            mockBibleManager.setCachedChapter("Psalms", ch, listOf(ch to "Verse $ch"))
        }

        // Act: Check if Psalms is cached
        val result = cacheManager.isBookCached(BibleBook("Psalms", 150, "Old"))

        // Assert: Should be true
        assertTrue("Should return true when all chapters are cached", result)
    }

    @Test
    fun isBookCachedReturnsFalseWhenAnyChapterMissing() {
        // Setup: Genesis chapters 1-49 cached, 50 missing
        (1..49).forEach { ch ->
            mockBibleManager.setCachedChapter("Genesis", ch, listOf(ch to "Verse $ch"))
        }

        // Act: Check if Genesis is cached
        val result = cacheManager.isBookCached(BibleBook("Genesis", 50, "Old"))

        // Assert: Should be false
        assertFalse("Should return false when any chapter is missing", result)
    }

    @Test
    fun cachedChapterCountReturnsAccurateNumber() {
        // Setup: Isaiah chapters 1-30 cached, 31-66 missing
        (1..30).forEach { ch ->
            mockBibleManager.setCachedChapter("Isaiah", ch, listOf(ch to "Verse $ch"))
        }

        // Act: Get cached chapter count
        val result = cacheManager.cachedChapterCount(BibleBook("Isaiah", 66, "Old"))

        // Assert: Should return 30
        assertEquals("Should return count of cached chapters", 30, result)
    }

    @Test
    fun cacheFractionReturnsCorrectRatio() {
        // Setup: Romans chapters 1-8 of 16 cached
        (1..8).forEach { ch ->
            mockBibleManager.setCachedChapter("Romans", ch, listOf(ch to "Verse $ch"))
        }

        // Act: Get cache fraction
        val result = cacheManager.cacheFraction(BibleBook("Romans", 16, "New"))

        // Assert: Should return 0.5 (8/16)
        assertEquals("Should return correct cache fraction", 0.5f, result, 0.001f)
    }

    @Test
    fun prefetchWholeBibleDoesNotIncludeDeuterocanonicalOrEthiopianByDefault() {
        // Setup: No chapters cached

        // Act: Prefetch whole Bible
        runBlocking {
            cacheManager.prefetchWholeBible()
        }

        // Assert: Should fetch only Protestant canon (66 books = 1189 chapters total)
        // OT: 39 books = 929 chapters
        // NT: 27 books = 260 chapters
        val protestantBooks = BOOKS.filter { it.canons.contains(Canon.Protestant) }
        val expectedChapterCount = protestantBooks.sumOf { it.chapters }

        assertEquals("Should prefetch Protestant canon only", expectedChapterCount, mockBibleManager.fetchChapterCallCount)
    }

    @Test
    fun cacheFirstBehaviorIsMaintainedAcrossMultipleRequests() {
        // Setup: Genesis 1 not cached

        // Act: Request Genesis 1 three times
        runBlocking { cacheManager.ensureChapter("Genesis", 1) }
        runBlocking { cacheManager.ensureChapter("Genesis", 1) }
        runBlocking { cacheManager.ensureChapter("Genesis", 1) }

        // Assert: Should fetch exactly once (cache-first)
        assertEquals("Should fetch only once despite multiple requests", 1, mockBibleManager.fetchChapterCallCount)
    }
}

// ========== MOCKS FOR TESTING ==========

class MockBibleManager : BibleManagerStub() {
    private val cachedChapters = mutableMapOf<String, MutableList<Pair<Int, String>>>()
    var fetchChapterCallCount = 0
    private var fetchShouldFail = false
    private var fetchShouldFailForChapters = emptySet<Int>()

    fun setCachedChapter(book: String, chapter: Int, verses: List<Pair<Int, String>>) {
        val key = "$book:$chapter"
        cachedChapters[key] = verses.toMutableList()
    }

    fun setFetchShouldFail(shouldFail: Boolean) {
        fetchShouldFail = shouldFail
    }

    fun setFetchShouldFailForChapters(chapters: Set<Int>) {
        fetchShouldFailForChapters = chapters
    }

    override suspend fun fetchChapter(book: String, chapter: Int, version: String): List<Pair<Int, String>> {
        fetchChapterCallCount++
        if (fetchShouldFail || chapter in fetchShouldFailForChapters) {
            throw IOException("Simulated fetch failure for $book $chapter")
        }

        // Simulate successful fetch
        val key = "$book:$chapter"
        val verses = (1..20).map { v -> v to "Verse $v" }
        cachedChapters[key] = verses.toMutableList()
        return verses
    }

    override fun getChapter(book: String, chapter: Int): List<Pair<Int, String>> {
        val key = "$book:$chapter"
        return cachedChapters[key] ?: emptyList()
    }
}

abstract class BibleManagerStub : BibleManagerInterface {
    override suspend fun fetchChapter(book: String, chapter: Int, version: String): List<Pair<Int, String>> {
        throw NotImplementedError("Stub")
    }
    override fun getChapter(book: String, chapter: Int): List<Pair<Int, String>> {
        throw NotImplementedError("Stub")
    }
}

interface BibleManagerInterface {
    suspend fun fetchChapter(book: String, chapter: Int, version: String): List<Pair<Int, String>>
    fun getChapter(book: String, chapter: Int): List<Pair<Int, String>>
}

class MockSettingsManager {
    var bibleGatewayVersion = "NKJV"
    var showApocrypha = false
    var showEthiopian = false
}

class MockContext {
    // Minimal Android Context stub for testing
}

import java.io.IOException