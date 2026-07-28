package com.bytecats.metanoia

import android.content.Context
import com.bytecats.metanoia.bible.BibleCacheManager
import com.bytecats.metanoia.bible.BibleDatabase
import com.bytecats.metanoia.bible.BibleManager
import com.bytecats.metanoia.models.BibleBook
import com.bytecats.metanoia.models.Verse
import com.bytecats.metanoia.settings.SettingsManager
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito
import org.mockito.kotlin.whenever

class BibleCacheManagerTest {

    private class FakeManager(
        context: Context,
        override val db: BibleDatabase,
        val fetcher: suspend (String, Int) -> List<Verse>,
    ) : BibleManager(context) {
        override suspend fun fetchChapter(book: String, chapter: Int, version: String): List<Verse> {
            return fetcher(book, chapter)
        }
    }

    private fun mockContextAndSettings(): Pair<Context, SettingsManager> {
        val context = Mockito.mock(Context::class.java)
        val settings = Mockito.mock(SettingsManager::class.java)
        whenever(settings.bibleGatewayVersion).thenReturn("NKJV")
        return context to settings
    }

    private fun fakeDb(book: String, chapters: Set<Int>): BibleDatabase {
        val db = Mockito.mock(BibleDatabase::class.java)
        Mockito.doAnswer { invocation ->
            val b = invocation.getArgument<String>(0)
            val c = invocation.getArgument<Int>(1)
            if (b == book && c in chapters) listOf(Verse(1, "text")) else emptyList()
        }.whenever(db).getChapter(Mockito.anyString(), Mockito.anyInt())
        return db
    }

    private fun emptyDb(): BibleDatabase = fakeDb("", emptySet())

    @Test
    fun cacheFractionZeroWhenEmpty() {
        val (context, settings) = mockContextAndSettings()
        val db = emptyDb()
        val manager = FakeManager(context, db) { _, _ -> emptyList() }
        val cache = BibleCacheManager(context, manager, settings)
        val book = BibleBook("Genesis", 50, "Old")
        assertEquals(0f, cache.cacheFraction(book), 0.001f)
        assertEquals(0, cache.cachedChapterCount(book))
    }

    @Test
    fun cacheFractionHalfWhenHalfCached() {
        val (context, settings) = mockContextAndSettings()
        val cached = (1..25).toSet()
        val db = fakeDb("Genesis", cached)
        val manager = FakeManager(context, db) { _, _ -> emptyList() }
        val cache = BibleCacheManager(context, manager, settings)
        val book = BibleBook("Genesis", 50, "Old")
        assertEquals(0.5f, cache.cacheFraction(book), 0.001f)
        assertEquals(25, cache.cachedChapterCount(book))
    }

    @Test
    fun ensureChapterUsesCacheWhenAvailable() {
        val (context, settings) = mockContextAndSettings()
        val db = fakeDb("Genesis", setOf(1))
        val manager = FakeManager(context, db) { _, _ ->
            throw AssertionError("fetchChapter should not be called when cached")
        }
        val cache = BibleCacheManager(context, manager, settings)
        val result = runBlocking { cache.ensureChapter("Genesis", 1) }
        assertTrue(result)
    }

    @Test
    fun ensureChapterFetchesWhenMissing() {
        val (context, settings) = mockContextAndSettings()
        val db = fakeDb("Genesis", emptySet())
        val manager = FakeManager(context, db) { book, chapter ->
            if (book == "Genesis" && chapter == 1) listOf(Verse(1, "In the beginning")) else emptyList()
        }
        val cache = BibleCacheManager(context, manager, settings)
        val result = runBlocking { cache.ensureChapter("Genesis", 1) }
        assertTrue(result)
    }

    @Test
    fun prefetchBookProgressesToCompletion() {
        val (context, settings) = mockContextAndSettings()
        val book = BibleBook("Tiny", 4, "New")
        val db = fakeDb("Tiny", emptySet())
        val manager = FakeManager(context, db) { b, c ->
            if (b == "Tiny") listOf(Verse(c, "v$c")) else emptyList()
        }
        val cache = BibleCacheManager(context, manager, settings)
        runBlocking { cache.prefetchBook(book) }
        assertEquals(1f, cache.prefetchProgress.value["Tiny"] ?: 0f, 0.001f)
        assertFalse(cache.prefetchErrors.value.containsKey("Tiny"))
    }

    @Test
    fun prefetchBookRecordsErrorOnFailure() {
        val (context, settings) = mockContextAndSettings()
        val book = BibleBook("Broken", 2, "New")
        val db = fakeDb("Broken", emptySet())
        val manager = FakeManager(context, db) { _, _ -> emptyList() }
        val cache = BibleCacheManager(context, manager, settings)
        runBlocking { cache.prefetchBook(book) }
        assertEquals(1f, cache.prefetchProgress.value["Broken"] ?: 0f, 0.001f)
        assertTrue(cache.prefetchErrors.value.containsKey("Broken"))
    }
}
