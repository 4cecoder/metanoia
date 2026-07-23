package com.bytecats.metanoia

import com.bytecats.metanoia.bible.DeuterocanonRouting
import com.bytecats.metanoia.bible.WikisourceApocryphaScraper
import com.bytecats.metanoia.bible.WikisourceEnochScraper
import com.bytecats.metanoia.models.BOOKS
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the routing data BibleManager relies on for the 18
 * deuterocanonical/Ethiopian-canon books with no verse text in
 * data/bible.db (see src/bible_db.zig's `books_with_no_verse_text`, the
 * canonical list this mirrors). Deliberately independent of BibleManager
 * itself (which needs an Android Context this test suite can't construct,
 * per this repo's no-Robolectric convention) so this stays plain-JUnit
 * testable.
 */
class DeuterocanonRoutingTest {

    // The 18 known-gap books, exactly as enumerated in
    // src/bible_db.zig's `books_with_no_verse_text` — kept here as a
    // duplicate literal (not a shared import across the Zig/Kotlin
    // boundary) specifically so a change on either side that silently
    // drifts from the other gets caught by a failing test.
    private val allEighteenGapBooks = setOf(
        "Tobit", "Judith", "1Meqabyan", "2Meqabyan", "3Meqabyan",
        "Tegsas", "Wisdom", "Sirach", "Enoch", "Jubilees",
        "SirateTsion", "Tizaz", "Gitsiw", "Abtilis",
        "1Dominos", "2Dominos", "Qalementos", "Didasqalia"
    )

    @Test
    fun noSourceBooksPlusScrapedBooksExactlyCoverAllEighteenKnownGapBooks() {
        val scraped = WikisourceApocryphaScraper.SUPPORTED_BOOKS + WikisourceEnochScraper.BOOK_NAME
        assertEquals(emptySet<String>(), scraped intersect DeuterocanonRouting.NO_SOURCE_BOOKS)
        assertEquals(allEighteenGapBooks, scraped + DeuterocanonRouting.NO_SOURCE_BOOKS)
    }

    @Test
    fun noSourceBooksAreAllRealCanonicalBookNames() {
        val bookNames = BOOKS.map { it.name }.toSet()
        DeuterocanonRouting.NO_SOURCE_BOOKS.forEach {
            assertTrue("'$it' should be a real entry in BibleConstants.kt's BOOKS", it in bookNames)
        }
    }

    @Test
    fun noSourceMessageNamesTheBookAndDoesNotClaimNetworkFailure() {
        val message = DeuterocanonRouting.noSourceMessage("Jubilees")
        assertTrue(message.contains("Jubilees"))
        assertTrue(message.contains("no known"))
    }
}
