package com.bytecats.metanoia.models

import com.bytecats.metanoia.models.Canon
import com.bytecats.metanoia.models.CanonPresets
import com.bytecats.metanoia.models.TextTradition
import com.bytecats.metanoia.models.BookSection
import org.junit.Assert.*
import org.junit.Test

/**
 * Tests for the new canon-aware Bible book system.
 *
 * This ensures:
 * 1. Books belong to correct canons
 * 2. Filtering by canon works correctly
 * 3. Sectional grouping is accurate
 * 4. Textual tradition assignments are correct
 * 5. User preferences map to appropriate canon presets
 */
class CanonAwareBibleBookTest {

    @Test
    fun protestantCanonHasExactly66Books() {
        val protestantBooks = BOOKS.filterByCanon(Canon.Protestant)
        assertEquals("Protestant canon should have 66 books", 66, protestantBooks.size)
    }

    @Test
    fun catholicCanonHasMoreThan66Books() {
        val catholicBooks = BOOKS.filterByCanon(Canon.Catholic)
        assertTrue("Catholic canon should have more than 66 books", catholicBooks.size > 66)
        assertTrue("Catholic canon should include all Protestant books",
            BOOKS.filterByCanon(Canon.Protestant).all { it in catholicBooks })
    }

    @Test
    fun ethiopianCanonIsBroadest() {
        val protestantBooks = BOOKS.filterByCanon(Canon.Protestant)
        val ethiopianBooks = BOOKS.filterByCanon(Canon.Ethiopian)

        assertTrue("Ethiopian canon should be broader than Protestant",
            ethiopianBooks.size > protestantBooks.size)

        // Ethiopian should include unique books not in Protestant
        val ethiopianExclusive = ethiopianBooks.filter { Canon.Protestant !in it.canons }
        assertTrue("Ethiopian canon should have exclusive books", ethiopianExclusive.isNotEmpty())
    }

    @Test
    fun wisdomIsInCatholicAndOrthodoxButNotProtestant() {
        val wisdom = BOOKS.find { it.name == "Wisdom" }
        assertNotNull("Wisdom should exist in BOOKS", wisdom)

        assertTrue("Wisdom should be in Catholic canon", Canon.Catholic in wisdom!!.canons)
        assertTrue("Wisdom should be in Orthodox canon", Canon.Orthodox in wisdom.canons)
        assertFalse("Wisdom should NOT be in Protestant canon", Canon.Protestant in wisdom.canons)
    }

    @Test
    fun psalmsIsInAllCanons() {
        val psalms = BOOKS.find { it.name == "Psalms" }
        assertNotNull("Psalms should exist in BOOKS", psalms)

        assertEquals("Psalms should be in all canons",
            setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
            psalms!!.canons)
    }

    @Test
    fun enochIsOnlyInEthiopianCanon() {
        val enoch = BOOKS.find { it.name == "Enoch" }
        assertNotNull("Enoch should exist in BOOKS", enoch)

        assertTrue("Enoch should be in Ethiopian canon", Canon.Ethiopian in enoch!!.canons)
        assertFalse("Enoch should NOT be in Protestant canon", Canon.Protestant in enoch.canons)
        assertFalse("Enoch should NOT be in Catholic canon", Canon.Catholic in enoch.canons)
        assertFalse("Enoch should NOT be in Orthodox canon", Canon.Orthodox in enoch.canons)
        assertTrue("Enoch should be marked as Ethiopian exclusive", enoch.isEthiopianExclusive)
    }

    @Test
    fun oldTestamentBooksUseMasoreticOrSeptuagintTradition() {
        val otBooks = BOOKS.filter { it.testament == "Old" }
        otBooks.forEach { book ->
            assertTrue("Old Testament book ${book.name} should use Masoretic or Septuagint tradition",
                book.textTradition in setOf(TextTradition.Masoretic, TextTradition.Septuagint, TextTradition.Ethiopic))
        }
    }

    @Test
    fun newTestamentBooksUseNewTestamentTradition() {
        val ntBooks = BOOKS.filter { it.testament == "New" }
        ntBooks.forEach { book ->
            assertEquals("New Testament book ${book.name} should use NewTestament tradition",
                TextTradition.NewTestament, book.textTradition)
        }
    }

    @Test
    fun wisdomIsSeptuagintTradition() {
        val wisdom = BOOKS.find { it.name == "Wisdom" }
        assertNotNull("Wisdom should exist", wisdom)
        assertEquals("Wisdom should be Septuagint tradition", TextTradition.Septuagint, wisdom!!.textTradition)
        assertTrue("Wisdom should be Septuagint", wisdom.isSeptuagint)
    }

    @Test
    fun genesisIsMasoreticTradition() {
        val genesis = BOOKS.find { it.name == "Genesis" }
        assertNotNull("Genesis should exist", genesis)
        assertEquals("Genesis should be Masoretic tradition", TextTradition.Masoretic, genesis!!.textTradition)
        assertFalse("Genesis should not be Septuagint", genesis.isSeptuagint)
    }

    @Test
    fun pentateuchBooksHaveCorrectSection() {
        val pentateuchNames = setOf("Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy")
        val pentateuchBooks = BOOKS.filter { it.name in pentateuchNames }

        pentateuchBooks.forEach { book ->
            assertEquals("${book.name} should be in Pentateuch section",
                BookSection.Pentateuch, book.section)
        }
    }

    @Test
    fun wisdomBooksHaveCorrectSection() {
        val wisdomBookNames = setOf("Job", "Psalms", "Proverbs", "Ecclesiastes", "SongofSolomon", "Wisdom", "Sirach", "Baruch")
        val wisdomBooks = BOOKS.filter { it.name in wisdomBookNames }

        wisdomBooks.forEach { book ->
            assertEquals("${book.name} should be in Wisdom section",
                BookSection.Wisdom, book.section)
        }
    }

    @Test
    fun gospelsHaveCorrectSection() {
        val gospelNames = setOf("Matthew", "Mark", "Luke", "John")
        val gospels = BOOKS.filter { it.name in gospelNames }

        gospels.forEach { book ->
            assertEquals("${book.name} should be in Gospels section",
                BookSection.Gospels, book.section)
        }
    }

    @Test
    fun paulineEpistlesHaveCorrectSection() {
        val paulineNames = setOf("Romans", "1Corinthians", "2Corinthians", "Galatians",
            "Ephesians", "Philippians", "Colossians", "1Thessalonians", "2Thessalonians",
            "1Timothy", "2Timothy", "Titus", "Philemon")
        val pauline = BOOKS.filter { it.name in paulineNames }

        pauline.forEach { book ->
            assertEquals("${book.name} should be in PaulineEpistles section",
                BookSection.PaulineEpistles, book.section)
        }
    }

    @Test
    fun filterBySectionReturnsCorrectBooks() {
        val wisdomBooks = BOOKS.filterBySection(BookSection.Wisdom)
        val wisdomBookNames = wisdomBooks.map { it.name }.toSet()

        assertTrue("Wisdom section should include Job", "Job" in wisdomBookNames)
        assertTrue("Wisdom section should include Psalms", "Psalms" in wisdomBookNames)
        assertTrue("Wisdom section should include Proverbs", "Proverbs" in wisdomBookNames)
        assertTrue("Wisdom section should include Wisdom", "Wisdom" in wisdomBookNames)
        assertTrue("Wisdom section should include Sirach", "Sirach" in wisdomBookNames)

        assertFalse("Wisdom section should NOT include Genesis", "Genesis" in wisdomBookNames)
        assertFalse("Wisdom section should NOT include Matthew", "Matthew" in wisdomBookNames)
    }

    @Test
    fun groupBySectionCreatesLogicalGroupings() {
        val sections = BOOKS.groupBySection()

        assertTrue("Should have Gospels section", BookSection.Gospels in sections)
        assertTrue("Should have Wisdom section", BookSection.Wisdom in sections)
        assertTrue("Should have Pentateuch section", BookSection.Pentateuch in sections)

        assertEquals("Gospels section should have 4 books", 4, sections[BookSection.Gospels]!!.size)
        assertEquals("Pentateuch section should have 5 books", 5, sections[BookSection.Pentateuch]!!.size)

        val gospelNames = sections[BookSection.Gospels]!!.map { it.name }
        assertEquals("Gospels should be Matthew, Mark, Luke, John",
            setOf("Matthew", "Mark", "Luke", "John"), gospelNames.toSet())
    }

    @Test
    fun inCanonicalOrderForPreservesCanonicalOrder() {
        val protestantBooks = BOOKS.inCanonicalOrderFor(CanonPresets.PROTESTANT)
        val firstBook = protestantBooks.first()
        val lastBook = protestantBooks.last()

        assertEquals("First Protestant book should be Genesis", "Genesis", firstBook.name)
        assertEquals("Last Protestant book should be Revelation", "Revelation", lastBook.name)

        // Genesis should come before Exodus
        val genesisIndex = protestantBooks.indexOfFirst { it.name == "Genesis" }
        val exodusIndex = protestantBooks.indexOfFirst { it.name == "Exodus" }
        assertTrue("Genesis should come before Exodus", genesisIndex < exodusIndex)

        // First book should be Pentateuch (Genesis)
        assertTrue("First book should be in Pentateuch section", firstBook.section == BookSection.Pentateuch)

        // Last book should be Apocalyptic (Revelation)
        assertTrue("Last book should be in Apocalyptic section", lastBook.section == BookSection.Apocalyptic)
    }

    @Test
    fun canonPresetFromUserPreferencesReturnsCorrectPreset() {
        // No extra books = Protestant
        val protestantPreset = CanonPresets.fromUserPreferences(showApocrypha = false, showEthiopian = false)
        assertEquals("No preferences should return Protestant", CanonPresets.PROTESTANT, protestantPreset)

        // Apocrypha only = Orthodox
        val orthodoxPreset = CanonPresets.fromUserPreferences(showApocrypha = true, showEthiopian = false)
        assertEquals("Apocrypha only should return Orthodox", CanonPresets.ORTHODOX, orthodoxPreset)

        // Ethiopian only = Ethiopian
        val ethiopianPreset = CanonPresets.fromUserPreferences(showApocrypha = false, showEthiopian = true)
        assertEquals("Ethiopian only should return Ethiopian", CanonPresets.ETHIOPIAN, ethiopianPreset)

        // Both = Ethiopian (broadest)
        val broadestPreset = CanonPresets.fromUserPreferences(showApocrypha = true, showEthiopian = true)
        assertEquals("Both preferences should return Ethiopian", CanonPresets.ETHIOPIAN, broadestPreset)
    }

    @Test
    fun canonicalStatusReturnsHumanReadableDescriptions() {
        val psalms = BOOKS.find { it.name == "Psalms" }!!
        assertEquals("Universal book should say 'Universal'", "Universal", psalms.canonicalStatus())

        val wisdom = BOOKS.find { it.name == "Wisdom" }!!
        val wisdomStatus = wisdom.canonicalStatus()
        assertTrue("Deuterocanonical book should mention 'Catholic'", wisdomStatus.contains("Catholic"))

        val enoch = BOOKS.find { it.name == "Enoch" }!!
        assertEquals("Ethiopian-exclusive book should say 'Ethiopian Only'", "Ethiopian Only", enoch.canonicalStatus())

        val genesis = BOOKS.find { it.name == "Genesis" }!!
        assertEquals("Universal book (in all canons) should say 'Universal'", "Universal", genesis.canonicalStatus())
    }

    @Test
    fun isDeuterocanonicalIdentifiesCatholicOrthodoxOnlyBooks() {
        val wisdom = BOOKS.find { it.name == "Wisdom" }!!
        assertTrue("Wisdom should be deuterocanonical", wisdom.isDeuterocanonical)

        val genesis = BOOKS.find { it.name == "Genesis" }!!
        assertFalse("Genesis should NOT be deuterocanonical", genesis.isDeuterocanonical)

        val psalms = BOOKS.find { it.name == "Psalms" }!!
        assertFalse("Psalms should NOT be deuterocanonical (in all canons)", psalms.isDeuterocanonical)
    }

    @Test
    fun strongsLanguagePrefixReturnsCorrectPrefix() {
        assertEquals("Genesis (Masoretic) should use Hebrew", "H",
            strongsLanguagePrefix("Genesis"))

        assertEquals("Matthew (New Testament) should use Greek", "G",
            strongsLanguagePrefix("Matthew"))

        assertEquals("Wisdom (Septuagint) should use Greek", "G",
            strongsLanguagePrefix("Wisdom"))

        assertEquals("Enoch (Ethiopic) should use Greek", "G",
            strongsLanguagePrefix("Enoch"))
    }

    @Test
    fun totalBookCountIsReasonable() {
        val totalBooks = BOOKS.size

        // Should be more than 66 (Protestant)
        assertTrue("Should have more than Protestant canon (66)", totalBooks > 66)

        // Should be more than 73 (Catholic)
        assertTrue("Should have more than Catholic canon (73)", totalBooks > 73)

        // Should be at least 81 (Ethiopian)
        assertTrue("Should have at least Ethiopian canon (81)", totalBooks >= 81)

        // Should not be absurdly high (sanity check)
        assertTrue("Should not have more than 100 books", totalBooks < 100)
    }

    @Test
    fun noDuplicateBookNames() {
        val bookNames = BOOKS.map { it.name }
        val uniqueNames = bookNames.toSet()
        assertEquals("All book names should be unique", bookNames.size, uniqueNames.size)
    }

    @Test
    fun allBooksHaveValidChapterCounts() {
        BOOKS.forEach { book ->
            assertTrue("${book.name} should have at least 1 chapter", book.chapters > 0)

            // Sanity check: no book should have absurdly high chapter count
            assertTrue("${book.name} should have reasonable chapter count", book.chapters < 200)
        }
    }

    @Test
    fun allBooksBelongToAtLeastOneCanon() {
        BOOKS.forEach { book ->
            assertTrue("${book.name} should belong to at least one canon", book.canons.isNotEmpty())
        }
    }

    @Test
    fun allBooksHaveTestamentAssigned() {
        val validTestaments = setOf("Old", "New", "Eth")
        BOOKS.forEach { book ->
            assertTrue("${book.name} should have valid testament", book.testament in validTestaments)
        }
    }
}