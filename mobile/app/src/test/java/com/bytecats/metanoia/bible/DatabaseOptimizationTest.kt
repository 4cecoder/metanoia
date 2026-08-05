package com.bytecats.metanoia.bible

import androidx.test.core.app.ApplicationProvider
import com.bytecats.metanoia.models.Verse
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class DatabaseOptimizationTest {

    private lateinit var db: BibleDatabase

    @Before
    fun setup() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        db = BibleDatabase(context)
        // ensure db is initialized
        db.exists()
    }

    @After
    fun teardown() {
        db.open(false).close()
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getDatabasePath("bible.db").delete()
        context.filesDir.resolve("bible.db").delete()
    }

    @Test
    fun testVerseFtsSearchPerformanceOptimization() {
        // Given verses
        val verses = listOf(
            Verse(1, "In the beginning God created the heaven and the earth."),
            Verse(2, "And the earth was without form, and void; and darkness was upon the face of the deep.")
        )
        db.insertVerses("Genesis", 1, verses, "KJV")
        db.insertVerses("John", 1, listOf(Verse(1, "In the beginning was the Word, and the Word was with God, and the Word was God.")), "KJV")

        // When searching with a word that appears in multiple verses
        val results = db.searchVerses("beginning")

        // Then both verses should be found, and it should be fast (FTS)
        assertEquals(2, results.size)
        assertTrue(results.any { it.book == "Genesis" })
        assertTrue(results.any { it.book == "John" })
    }

    @Test
    fun testBookCompletionQueryOptimization() {
        db.insertVerses("Genesis", 1, listOf(Verse(1, "Test"), Verse(2, "Test2")), "KJV")
        db.insertVerses("Genesis", 2, listOf(Verse(1, "Test")), "KJV")

        val completion = db.getBookCompletion()
        // We know Genesis has 50 chapters, we inserted 2
        val expectedRatio = 2f / 50f
        assertEquals(expectedRatio, completion["Genesis"] ?: 0f, 0.001f)
    }

    @Test
    fun testGetStatsOptimization() {
        db.insertVerses("Genesis", 1, listOf(Verse(1, "Test")), "KJV")
        db.insertVerses("Matthew", 1, listOf(Verse(1, "Test")), "KJV")

        val stats = db.getStats()
        assertEquals(1, stats.versesOt)
        assertEquals(1, stats.versesNt)
    }
}
