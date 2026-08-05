package com.bytecats.metanoia.bible

import org.junit.Assert.assertEquals
import org.junit.Test

class WordCountMetricsTest {

    @Test
    fun testCalculateWordCount() {
        assertEquals(0, ReadingStats.calculateWordCount(""))
        assertEquals(0, ReadingStats.calculateWordCount("   "))
        assertEquals(1, ReadingStats.calculateWordCount("Hello"))
        assertEquals(5, ReadingStats.calculateWordCount("Hello world, this is  Kotlin."))
        assertEquals(5, ReadingStats.calculateWordCount("   Hello   world, this is Kotlin.  "))
    }

    @Test
    fun testFormatReadingTime() {
        assertEquals("< 1 min", ReadingStats.formatReadingTime(0))
        assertEquals("< 1 min", ReadingStats.formatReadingTime(100))
        assertEquals("1 min", ReadingStats.formatReadingTime(200))
        assertEquals("1 min", ReadingStats.formatReadingTime(201))
        assertEquals("2 min", ReadingStats.formatReadingTime(400))
        assertEquals("2 min", ReadingStats.formatReadingTime(401))
    }

    @Test
    fun testCalculateBookWordCount() {
        val chapterCounts = mapOf(
            1 to 100,
            2 to 200,
            3 to 150
        )
        assertEquals(450, ReadingStats.calculateBookWordCount(chapterCounts))
        assertEquals(0, ReadingStats.calculateBookWordCount(emptyMap()))
    }
}
