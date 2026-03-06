package com.bytecats.metanoia

import com.bytecats.metanoia.models.BIBLE_ABBREVIATIONS
import org.junit.Assert.assertEquals
import org.junit.Test

class BibleConstantsTest {
    @Test
    fun testAbbreviationMapping() {
        assertEquals("John", BIBLE_ABBREVIATIONS["jn"])
        assertEquals("Genesis", BIBLE_ABBREVIATIONS["gen"])
        assertEquals("Revelation", BIBLE_ABBREVIATIONS["rev"])
        assertEquals("1John", BIBLE_ABBREVIATIONS["1jn"])
    }
}
