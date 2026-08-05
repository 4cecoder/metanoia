package com.bytecats.metanoia.bible

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class UniversalBibleSearchTest {

    private val search = UniversalBibleSearch()

    @Test
    fun testAbbreviationResolution() {
        assertEquals("John", search.resolveBookAbbreviation("jn"))
        assertEquals("John", search.resolveBookAbbreviation("John"))
        assertEquals("1 John", search.resolveBookAbbreviation("1jn"))
        assertEquals("Genesis", search.resolveBookAbbreviation("gen"))
        assertEquals("Revelation", search.resolveBookAbbreviation("rev"))
        assertEquals("1 Enoch", search.resolveBookAbbreviation("enoch"))
        assertNull(search.resolveBookAbbreviation("nonexistentbook"))
    }

    @Test
    fun testReferenceParsing() {
        val ref1 = search.parseReference("John 3:16")
        assertNotNull(ref1)
        assertEquals("John", ref1?.book)
        assertEquals(3, ref1?.chapter)
        assertEquals(16, ref1?.verse)

        val ref2 = search.parseReference("1 John 3:16")
        assertNotNull(ref2)
        assertEquals("1 John", ref2?.book)
        assertEquals(3, ref2?.chapter)
        assertEquals(16, ref2?.verse)

        val ref3 = search.parseReference("jn 3:16")
        assertNotNull(ref3)
        assertEquals("John", ref3?.book)
        assertEquals(3, ref3?.chapter)
        assertEquals(16, ref3?.verse)

        val ref4 = search.parseReference("Romans 8")
        assertNotNull(ref4)
        assertEquals("Romans", ref4?.book)
        assertEquals(8, ref4?.chapter)
        assertNull(ref4?.verse)
    }
}
