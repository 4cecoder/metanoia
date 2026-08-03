package com.bytecats.metanoia.bible

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
    //
    // NEW: Uses textTradition instead of testament. Masoretic (Hebrew) books use "H".
    // Septuagint (Greek) deuterocanonical books, New Testament (Greek), and
    // Ethiopian-canon-only books (Ge'ez) all use "G".

    @Test
    fun strongsLanguagePrefixIsHebrewForMasoreticBooks() {
        val masoreticBooks = BOOKS.filter { it.textTradition == com.bytecats.metanoia.models.TextTradition.Masoretic }
        // Sanity check the fixture actually includes the tricky cases
        val namesCovered = masoreticBooks.map { it.name }.toSet()
        listOf(
            "Genesis", "Exodus", "Psalms", "Proverbs", "Isaiah", "Job", "SongofSolomon"
        ).forEach { assertTrue("Expected BOOKS to still contain '$it'", namesCovered.contains(it)) }

        masoreticBooks.forEach { book ->
            assertEquals(
                "Expected Hebrew (\"H\") prefix for Masoretic book '${book.name}'",
                "H", strongsLanguagePrefix(book.name)
            )
        }
    }

    @Test
    fun strongsLanguagePrefixIsGreekForSeptuagintDeuterocanonical() {
        // Deuterocanonical books are in the Old Testament (testament == "Old") but
        // are part of the Greek Septuagint tradition, so they should use "G"
        val septuagintBooks = BOOKS.filter { it.textTradition == com.bytecats.metanoia.models.TextTradition.Septuagint }
        // Sanity check we have deuterocanonical books
        val namesCovered = septuagintBooks.map { it.name }.toSet()
        listOf("Wisdom", "Sirach", "Tobit", "Judith").forEach {
            assertTrue("Expected BOOKS to still contain deuterocanonical '$it'", namesCovered.contains(it))
        }

        septuagintBooks.forEach { book ->
            assertEquals(
                "Expected Greek (\"G\") prefix for Septuagint book '${book.name}'",
                "G", strongsLanguagePrefix(book.name)
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
