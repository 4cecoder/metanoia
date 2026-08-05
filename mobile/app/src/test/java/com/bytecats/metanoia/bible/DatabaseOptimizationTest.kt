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
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getDatabasePath("bible.db").delete()
        context.filesDir.resolve("bible.db").delete()
    }

    @Test
    fun testVerseFtsSearchPerformanceOptimization() {
        val verses = listOf(
            Verse(1, "In the beginning God created the heaven and the earth."),
            Verse(2, "And the earth was without form, and void; and darkness was upon the face of the deep.")
        )
        db.open(false).use { database ->
            database.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES ('Genesis', 1, 1, 'In the beginning God created the heaven and the earth.', 'KJV')")
            database.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES ('Genesis', 1, 2, 'And the earth was without form, and void; and darkness was upon the face of the deep.', 'KJV')")
            database.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES ('John', 1, 1, 'In the beginning was the Word, and the Word was with God, and the Word was God.', 'KJV')")
        }

        val results = db.searchVerses("beginning")
        assertTrue(results.isNotEmpty())
    }

    @Test
    fun testBookCompletionQueryOptimization() {
        db.open(false).use { database ->
            database.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES ('Genesis', 1, 1, 'Test', 'KJV')")
            database.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES ('Genesis', 2, 1, 'Test2', 'KJV')")
        }

        val completion = db.getBookCompletion()
        val expectedRatio = 2f / 50f
        assertEquals(expectedRatio, completion["Genesis"] ?: 0f, 0.001f)
    }

    @Test
    fun testGetStatsOptimization() {
        db.open(false).use { database ->
            database.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES ('Genesis', 1, 1, 'Test', 'KJV')")
            database.execSQL("INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES ('Matthew', 1, 1, 'Test', 'KJV')")
        }

        val stats = db.getStats()
        assertTrue(stats.versesOt >= 1)
        assertTrue(stats.versesNt >= 1)
    }
}
