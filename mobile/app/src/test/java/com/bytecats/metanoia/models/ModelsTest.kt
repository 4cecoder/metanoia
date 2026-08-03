package com.bytecats.metanoia.models

import com.bytecats.metanoia.models.*
import com.bytecats.metanoia.viewmodel.NarrationState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelsTest {

    @Test
    fun verseDataClass() {
        val v = Verse(1, "In the beginning God created the heavens and the earth.")
        assertEquals(1, v.number)
        assertEquals("In the beginning God created the heavens and the earth.", v.text)
    }

    @Test
    fun lexiconEntryDataClass() {
        val e = LexiconEntry("אֱלֹהִים", "God, gods, judges")
        assertEquals("אֱלֹהִים", e.lemma)
        assertEquals("God, gods, judges", e.definition)
    }

    @Test
    fun verseListOperations() {
        val verses = listOf(
            Verse(1, "Verse one"),
            Verse(2, "Verse two"),
            Verse(3, "Verse three")
        )
        assertEquals(3, verses.size)
        assertEquals("Verse two", verses.find { it.number == 2 }?.text)
    }

    @Test
    fun bibleBookStructure() {
        val gen = BibleBook("Genesis", 50, "Old")
        assertEquals("Genesis", gen.name)
        assertEquals(50, gen.chapters)
        assertEquals("Old", gen.testament)
    }

    @Test
    fun narrationStateTransitions() {
        val state = NarrationState(
            isPlaying = true,
            currentVerse = 5,
            queue = listOf(Verse(1, "a"), Verse(5, "e"))
        )
        assertEquals(5, state.currentVerse)
        val stopped = state.copy(isPlaying = false)
        assertEquals(false, stopped.isPlaying)
    }

    @Test
    fun booksListContainsExpectedEntries() {
        assertEquals("Genesis", BOOKS.first().name)
        assertTrue(BOOKS.any { it.name == "Revelation" })
        assertTrue(BOOKS.size >= 80)
    }

    @Test
    fun abbreviationMapping() {
        assertEquals("John", BIBLE_ABBREVIATIONS["jn"])
        assertEquals("Genesis", BIBLE_ABBREVIATIONS["gen"])
        assertEquals("1John", BIBLE_ABBREVIATIONS["1jn"])
    }
}
