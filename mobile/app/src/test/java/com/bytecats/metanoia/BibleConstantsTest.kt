package com.bytecats.metanoia

import com.bytecats.metanoia.models.BIBLE_ABBREVIATIONS
import com.bytecats.metanoia.models.BOOKS
import com.bytecats.metanoia.models.strongsLanguagePrefix
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BibleConstantsTest {
    @Test
    fun testAbbreviationMapping() {
        assertEquals("John", BIBLE_ABBREVIATIONS["jn"])
        assertEquals("Genesis", BIBLE_ABBREVIATIONS["gen"])
        assertEquals("Revelation", BIBLE_ABBREVIATIONS["rev"])
        assertEquals("1John", BIBLE_ABBREVIATIONS["1jn"])
    }

    // --- strongsLanguagePrefix: guards against the language-prefix drift bug
    // class already found and fixed in tools/interlinear_scraper.py, where a
    // hand-maintained OT book list drifted from the canonical testament data
    // (e.g. "Song of Solomon" with a space vs. the app's "SongofSolomon", and
    // deuterocanonical/Ethiopian-canon OT books silently falling through to
    // the wrong "G" prefix). strongsLanguagePrefix reads BOOKS directly, so
    // there is only one source of truth and it cannot drift like that again.

    @Test
    fun strongsLanguagePrefixIsHebrewForEveryOldTestamentBook() {
        val oldTestamentBooks = BOOKS.filter { it.testament == "Old" }
        // Sanity check the fixture itself actually includes the tricky cases
        // this test exists to guard, so a future BOOKS edit can't silently
        // drop them without failing this test.
        val namesCovered = oldTestamentBooks.map { it.name }.toSet()
        listOf(
            "Genesis", "SongofSolomon", "Tobit", "Judith", "Sirach",
            "Enoch", "Jubilees", "1Meqabyan", "2Meqabyan", "3Meqabyan", "Wisdom"
        ).forEach { assertTrue("Expected BOOKS to still contain '$it'", namesCovered.contains(it)) }

        oldTestamentBooks.forEach { book ->
            assertEquals(
                "Expected Hebrew (\"H\") prefix for Old Testament book '${book.name}'",
                "H", strongsLanguagePrefix(book.name)
            )
        }
    }

    @Test
    fun strongsLanguagePrefixIsGreekForEveryNewTestamentBook() {
        BOOKS.filter { it.testament == "New" }.forEach { book ->
            assertEquals(
                "Expected Greek (\"G\") prefix for New Testament book '${book.name}'",
                "G", strongsLanguagePrefix(book.name)
            )
        }
    }

    @Test
    fun strongsLanguagePrefixIsGreekForEthiopianCanonOnlyBooks() {
        // "Eth" books (e.g. SirateTsion, Qalementos) are neither Old nor New
        // Testament. They must not silently fall through to the Hebrew
        // prefix just because they aren't "New" -- that was the same shape
        // of bug the Python scraper's drifted book list produced.
        val ethBooks = BOOKS.filter { it.testament == "Eth" }
        assertTrue("Expected at least one Eth-testament book in BOOKS", ethBooks.isNotEmpty())
        ethBooks.forEach { book ->
            assertEquals(
                "Expected Greek (\"G\") prefix for Ethiopian-canon book '${book.name}'",
                "G", strongsLanguagePrefix(book.name)
            )
        }
    }

    @Test
    fun strongsLanguagePrefixDefaultsToGreekForUnrecognizedBookNames() {
        // A typo'd or mismatched book name (e.g. a name-format mismatch like
        // "Song of Solomon" with a space instead of "SongofSolomon") must not
        // silently resolve to Hebrew -- it should default the same way
        // tools/interlinear_scraper.py's language_prefix() does.
        assertEquals("G", strongsLanguagePrefix("Song of Solomon"))
        assertEquals("G", strongsLanguagePrefix("NotARealBook"))
    }
}
