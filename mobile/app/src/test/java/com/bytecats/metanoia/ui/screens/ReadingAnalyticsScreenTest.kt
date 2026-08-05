package com.bytecats.metanoia.ui.screens

import com.bytecats.metanoia.bible.ReadingStats
import com.bytecats.metanoia.models.BOOKS
import org.junit.Assert.assertEquals
import org.junit.Test

class ReadingAnalyticsScreenTest {

    @Test
    fun testOverallCompletionLogic() {
        val totalChapters = BOOKS.sumOf { it.chapters }
        val readCompletion = mapOf(
            "Genesis" to 0.5f,
            "Exodus" to 1.0f
        )
        
        val genesisTotal = BOOKS.find { it.name == "Genesis" }?.chapters ?: 0
        val exodusTotal = BOOKS.find { it.name == "Exodus" }?.chapters ?: 0
        
        val getBookTotalChapters: (String) -> Int = { name ->
            BOOKS.find { it.name == name }?.chapters ?: 0
        }
        
        val overallCompletion = ReadingStats.calculateOverallCompletion(
            readCompletion = readCompletion,
            getBookTotalChapters = getBookTotalChapters,
            totalChapters = totalChapters
        )
        
        val expectedReadChapters = (0.5f * genesisTotal).toInt() + (1.0f * exodusTotal).toInt()
        val expectedFraction = expectedReadChapters.toFloat() / totalChapters
        
        assertEquals(expectedFraction, overallCompletion, 0.0001f)
    }

    @Test
    fun testPerBookReadingProgressFractionsMatchChapterCounts() {
        val readCompletion = mapOf(
            "Genesis" to 0.5f,
            "Psalms" to 0.1f
        )
        
        val getBookTotalChapters: (String) -> Int = { name ->
            BOOKS.find { it.name == name }?.chapters ?: 0
        }
        
        val genesisTotal = getBookTotalChapters("Genesis")
        val psalmsTotal = getBookTotalChapters("Psalms")
        
        val readGenesisChapters = (readCompletion["Genesis"]!! * genesisTotal).toInt()
        val readPsalmsChapters = (readCompletion["Psalms"]!! * psalmsTotal).toInt()
        
        assertEquals((0.5f * 50).toInt(), readGenesisChapters)
        assertEquals((0.1f * 150).toInt(), readPsalmsChapters)
    }

    @Test
    fun testLerpColorReturnsExpectedColorBounds() {
        val fromColor = 0x000000
        val toColor = 0xFFFFFF
        
        val lowerBoundColor = ReadingStats.lerpColor(fromColor, toColor, 0f)
        assertEquals(0x000000, lowerBoundColor)
        
        val upperBoundColor = ReadingStats.lerpColor(fromColor, toColor, 1f)
        assertEquals(0xFFFFFF, upperBoundColor)
        
        val midBoundColor = ReadingStats.lerpColor(fromColor, toColor, 0.5f)
        assertEquals(0x7F7F7F, midBoundColor) // 0xFF / 2 = 127 = 0x7F

        // Test with the actual colors used in UI
        // val completionColor = Color(
        //     ReadingStats.lerpColor(neutralArgb, 0x9ece6a, overallFraction) or (0xFF shl 24)
        // )
        val neutralArgb = 0x222222
        val greenArgb = 0x9ece6a
        
        val minActual = ReadingStats.lerpColor(neutralArgb, greenArgb, 0f)
        assertEquals(neutralArgb, minActual)
        
        val maxActual = ReadingStats.lerpColor(neutralArgb, greenArgb, 1f)
        assertEquals(greenArgb, maxActual)
    }
}
