package com.bytecats.metanoia.ui.components

import androidx.compose.ui.graphics.Color
import com.bytecats.metanoia.ui.components.bible.hasHebrewChars
import com.bytecats.metanoia.ui.components.bible.verseBackground
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VerseItemEnhancementTest {

    @Test
    fun testHasHebrewChars_withHebrewText() {
        val hebrewText = "בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים"
        assertTrue("Expected to detect Hebrew characters", hasHebrewChars(hebrewText))
    }

    @Test
    fun testHasHebrewChars_withEnglishText() {
        val englishText = "In the beginning God created"
        assertFalse("Expected to not detect Hebrew characters", hasHebrewChars(englishText))
    }

    @Test
    fun testHasHebrewChars_withMixedText() {
        val mixedText = "God said יְהִי אוֹר"
        assertTrue("Expected to detect Hebrew characters in mixed text", hasHebrewChars(mixedText))
    }

    @Test
    fun testVerseBackground_isCurrent() {
        val primaryColor = Color(0xFF0000FF)
        val bgColor = verseBackground(isCurrent = true, highlight = 0, primary = primaryColor)
        // Should use primary color with alpha 0.15f
        assertEquals(primaryColor.copy(alpha = 0.15f), bgColor)
    }

    @Test
    fun testVerseBackground_isHighlighted() {
        val primaryColor = Color(0xFF0000FF)
        val highlightColorInt = 0xFFFF0000.toInt() // Red
        val bgColor = verseBackground(isCurrent = false, highlight = highlightColorInt, primary = primaryColor)
        
        // Should use highlight color with alpha 0.3f
        val expectedColor = Color(highlightColorInt.toLong()).copy(alpha = 0.3f)
        assertEquals(expectedColor, bgColor)
    }

    @Test
    fun testVerseBackground_currentAndHighlighted() {
        val primaryColor = Color(0xFF0000FF)
        val highlightColorInt = 0xFFFF0000.toInt()
        
        // isCurrent takes precedence
        val bgColor = verseBackground(isCurrent = true, highlight = highlightColorInt, primary = primaryColor)
        assertEquals(primaryColor.copy(alpha = 0.15f), bgColor)
    }

    @Test
    fun testVerseBackground_default() {
        val primaryColor = Color(0xFF0000FF)
        val bgColor = verseBackground(isCurrent = false, highlight = 0, primary = primaryColor)
        assertEquals(Color.Transparent, bgColor)
    }
}
