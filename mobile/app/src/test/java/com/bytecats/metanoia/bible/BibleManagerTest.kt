package com.bytecats.metanoia.bible

import com.bytecats.metanoia.models.*
import org.junit.Assert.*
import org.junit.Test

class BibleManagerTest {

    @Test
    fun verseListBuilding() {
        val verses = listOf(
            Verse(1, "In the beginning God created the heavens and the earth."),
            Verse(2, "The earth was without form, and void; and darkness was on the face of the deep.")
        )
        assertEquals(2, verses.size)
        assertEquals(1, verses.first().number)
        assertTrue(verses.any { it.text.contains("darkness") })
    }

    @Test
    fun lexiconEntryUsage() {
        val entry = LexiconEntry("λόγος", "word, speech, message")
        assertEquals("λόγος", entry.lemma)
        assertEquals("word, speech, message", entry.definition)
    }

    @Test
    fun bibleBookEnumeration() {
        assertEquals(84, BOOKS.size)
        assertEquals("Old", BOOKS[0].testament)
        assertEquals("New", BOOKS.find { it.name == "Matthew" }?.testament)
        assertEquals("Eth", BOOKS.find { it.name == "SirateTsion" }?.testament)
    }

    @Test
    fun libraryStatsDefault() {
        val stats = LibraryStats(0, 0, 0, 0, 0, 0, 0, 0.0)
        assertEquals(0, stats.versesOt)
        assertEquals(0.0, stats.dbSizeMb, 0.001)
    }

    @Test
    fun abbreviationReverseLookup() {
        val abbr = BIBLE_ABBREVIATIONS.entries.find { it.value == "Genesis" }
        assertNotNull(abbr)
        assertEquals("gen", abbr?.key)
    }
}
