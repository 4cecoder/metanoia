package com.bytecats.metanoia.bible

import com.bytecats.metanoia.bible.UniversalBibleSearch
import com.bytecats.metanoia.models.BOOKS
import com.bytecats.metanoia.models.Canon
import com.bytecats.metanoia.models.TextTradition
import org.junit.Assert.*
import org.junit.Test

/**
 * Tests for universal Bible search.
 *
 * Ensures that search indexes ALL books across ALL canons.
 * Nothing is hidden. Protestant-centric bias is prevented.
 */
class UniversalBibleSearchTest {

    private val universalSearch = UniversalBibleSearch()

    @Test
    fun searchBooksFindsAllMatchingBooks() {
        val results = universalSearch.searchBooks("wisdom")

        // Should find both Wisdom (deuterocanonical) and any book with "wisdom" in section name
        val wisdomBook = results.find { it.name == "Wisdom" }
        assertNotNull("Should find Wisdom book", wisdomBook)

        // Should NOT filter out deuterocanonical books
        assertTrue("Results should include deuterocanonical books",
            results.any { Canon.Protestant !in it.canons })
    }

    @Test
    fun searchBooksIsCaseInsensitive() {
        val upperResults = universalSearch.searchBooks("PSALMS")
        val lowerResults = universalSearch.searchBooks("psalms")

        assertEquals("Case should not matter", upperResults.size, lowerResults.size)
    }

    @Test
    fun searchBooksSearchesTradition() {
        val results = universalSearch.searchBooks("septuagint")

        // Should find Septuagint books
        assertTrue("Should find Septuagint tradition",
            results.any { it.textTradition == TextTradition.Septuagint })
    }

    @Test
    fun getAllBooksByTraditionReturnsCorrectTraditions() {
        val byTradition = universalSearch.getAllBooksByTradition()

        assertTrue("Should have Masoretic tradition",
            byTradition.containsKey(TextTradition.Masoretic))
        assertTrue("Should have Septuagint tradition",
            byTradition.containsKey(TextTradition.Septuagint))
        assertTrue("Should have New Testament tradition",
            byTradition.containsKey(TextTradition.NewTestament))
        assertTrue("Should have Ethiopic tradition",
            byTradition.containsKey(TextTradition.Ethiopic))

        // Masoretic should have ~39 books
        val masoreticCount = byTradition[TextTradition.Masoretic]?.size ?: 0
        assertTrue("Masoretic should have ~39 books", masoreticCount > 30 && masoreticCount < 50)

        // New Testament should have exactly 27 books
        val ntCount = byTradition[TextTradition.NewTestament]?.size ?: 0
        assertEquals("New Testament should have exactly 27 books", 27, ntCount)
    }

    @Test
    fun getSeptuagintOnlyBooksReturnsGreekOTBooks() {
        val septuagintOnly = universalSearch.getSeptuagintOnlyBooks()

        // Should include Wisdom, Sirach, Tobit, Judith, etc.
        assertTrue("Should include Wisdom",
            septuagintOnly.any { it.name == "Wisdom" })
        assertTrue("Should include Sirach",
            septuagintOnly.any { it.name == "Sirach" })
        assertTrue("Should include Tobit",
            septuagintOnly.any { it.name == "Tobit" })

        // Should NOT include Masoretic books
        assertFalse("Should NOT include Genesis",
            septuagintOnly.any { it.name == "Genesis" })
        assertFalse("Should NOT include Psalms",
            septuagintOnly.any { it.name == "Psalms" })
    }

    @Test
    fun getEthiopicOnlyBooksReturnsGezBooks() {
        val ethiopicOnly = universalSearch.getEthiopicOnlyBooks()

        // Should include Enoch, Jubilees, Meqabyan
        assertTrue("Should include Enoch",
            ethiopicOnly.any { it.name == "Enoch" })
        assertTrue("Should include Jubilees",
            ethiopicOnly.any { it.name == "Jubilees" })
        assertTrue("Should include 1Meqabyan",
            ethiopicOnly.any { it.name == "1Meqabyan" })

        // Should NOT include universal books
        assertFalse("Should NOT include Psalms",
            ethiopicOnly.any { it.name == "Psalms" })
    }

    @Test
    fun getUniversalBooksReturnsBooksInAllCanons() {
        val universal = universalSearch.getUniversalBooks()

        // Psalms should be universal
        assertTrue("Psalms should be universal",
            universal.any { it.name == "Psalms" })

        // All universal books should have 4 canons
        assertTrue("All universal books should be in all 4 canons",
            universal.all { it.canons.size == 4 })

        // Genesis should be universal
        assertTrue("Genesis should be universal",
            universal.any { it.name == "Genesis" })
    }

    @Test
    fun getMissingFromProtestantReturnsApocrypha() {
        val missing = universalSearch.getMissingFromProtestant()

        // Should include deuterocanonical books
        assertTrue("Should include Wisdom",
            missing.any { it.name == "Wisdom" })
        assertTrue("Should include Tobit",
            missing.any { it.name == "Tobit" })
        assertTrue("Should include Judith",
            missing.any { it.name == "Judith" })

        // Should include Ethiopian-exclusive books
        assertTrue("Should include Enoch",
            missing.any { it.name == "Enoch" })
        assertTrue("Should include Jubilees",
            missing.any { it.name == "Jubilees" })

        // Should NOT include Protestant-only books
        assertFalse("Should NOT include Genesis",
            missing.any { it.name == "Genesis" })
    }

    @Test
    fun getCanonExclusiveBooksShowsDistribution() {
        val exclusives = universalSearch.getCanonExclusiveBooks()

        // Catholic-exclusive books (if any)
        val catholicExclusive = exclusives[Canon.Catholic] ?: emptyList()

        // Orthodox-exclusive books (if any)
        val orthodoxExclusive = exclusives[Canon.Orthodox] ?: emptyList()

        // Ethiopian-exclusive books
        val ethiopianExclusive = exclusives[Canon.Ethiopian] ?: emptyList()

        // Ethiopian should have exclusives
        assertTrue("Ethiopian should have exclusive books",
            ethiopianExclusive.isNotEmpty())
        assertTrue("Ethiopian exclusives should include Enoch",
            ethiopianExclusive.any { it.name == "Enoch" })

        // Protestant should have NO exclusive books (it's a subset)
        assertFalse("Protestant should NOT have exclusive books",
            exclusives.containsKey(Canon.Protestant))
    }

    @Test
    fun getCorpusStatisticsReturnsAccurateStats() {
        val stats = universalSearch.getCorpusStatistics()

        // Total books should be > 66 (more than Protestant)
        assertTrue("Total books should be more than Protestant (66)",
            stats.totalBooks > 66)

        // Should have all 4 traditions
        assertEquals("Should have all 4 traditions", 4, stats.byTradition.size)

        // Missing from Protestant should be > 0
        assertTrue("Should have books missing from Protestant",
            stats.missingFromProtestant > 0)

        // Ethiopian exclusive should be > 0
        assertTrue("Should have Ethiopian-exclusive books",
            stats.ethiopianExclusive > 0)

        // Section breakdown
        assertTrue("Should have section breakdown",
            stats.bySection.isNotEmpty())
    }

    @Test
    fun nothingIsHiddenInUniversalSearch() {
        val allBooks = BOOKS
        val septuagintOnly = universalSearch.getSeptuagintOnlyBooks()
        val ethiopicOnly = universalSearch.getEthiopicOnlyBooks()

        // Search for each unique book should find it
        septuagintOnly.forEach { book ->
            val results = universalSearch.searchBooks(book.name)
            assertTrue("${book.name} should be discoverable in universal search",
                results.any { it.name == book.name })
        }

        ethiopicOnly.forEach { book ->
            val results = universalSearch.searchBooks(book.name)
            assertTrue("${book.name} should be discoverable in universal search",
                results.any { it.name == book.name })
        }
    }

    @Test
    fun corpusStatisticsRevealsBreadth() {
        val stats = universalSearch.getCorpusStatistics()

        // Septuagint should have books
        assertTrue("Septuagint tradition should exist",
            stats.byTradition[TextTradition.Septuagint]!! > 0)

        // Ethiopic should have books
        assertTrue("Ethiopic tradition should exist",
            stats.byTradition[TextTradition.Ethiopic]!! > 0)

        // Books missing from Protestant should be a significant portion
        val missingPercentage = stats.missingFromProtestant.toFloat() / stats.totalBooks * 100
        assertTrue("Missing books should be significant portion (>5%)",
            missingPercentage > 5f)
    }

    @Test
    fun searchCanFindBySection() {
        val results = universalSearch.searchBooks("Gospel")

        // Should find all Gospels (Matthew, Mark, Luke, John)
        val gospels = results.filter { it.section.name == "Gospels" }
        assertTrue("Should find Gospels when searching for 'Gospel'",
            gospels.isNotEmpty())
    }

    @Test
    fun searchCanFindByTestament() {
        val oldTestamentResults = universalSearch.searchBooks("Old")
        val newTestamentResults = universalSearch.searchBooks("New")

        // Should find books from each testament
        assertTrue("Should find Old Testament books",
            oldTestamentResults.any { it.testament == "Old" })
        assertTrue("Should find New Testament books",
            newTestamentResults.any { it.testament == "New" })
    }
}