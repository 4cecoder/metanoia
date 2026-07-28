package com.bytecats.metanoia.bible

import com.bytecats.metanoia.models.BibleBook
import com.bytecats.metanoia.models.BOOKS
import com.bytecats.metanoia.models.TextTradition

/**
 * Universal Bible search that indexes ALL books across ALL canons.
 *
 * Unlike user-canonical search, this does NOT hide any books.
 * Everything is discoverable, searchable, and accessible.
 *
 * This prevents Protestant-centric bias from "burying" apocryphal
 * and Ethiopian texts from discovery.
 */
class UniversalBibleSearch {

    /**
     * Search ALL books across ALL canons.
     *
     * Returns books matching the query, regardless of user's canonical
     * preferences. Nothing is hidden.
     */
    fun searchBooks(query: String): List<BibleBook> {
        val lowerQuery = query.lowercase()
        return BOOKS.filter { book ->
            book.name.lowercase().contains(lowerQuery) ||
            book.section.name.lowercase().contains(lowerQuery) ||
            book.textTradition.name.lowercase().contains(lowerQuery) ||
            book.testament.lowercase().contains(lowerQuery)
        }
    }

    /**
     * Get ALL books organized by textual tradition.
     *
     * This reveals the full biblical corpus:
     * - Masoretic (Hebrew)
     * - Septuagint (Greek OT)
     * - New Testament (Greek)
     * - Ethiopic (Ge'ez)
     */
    fun getAllBooksByTradition(): Map<TextTradition, List<BibleBook>> {
        return BOOKS.groupBy { it.textTradition }
    }

    /**
     * Get books unique to Septuagint (not in Masoretic).
     *
     * These are the books Protestantism "buried" — deuterocanonical
     * books that exist in Catholic/Orthodox canons but NOT in
     * the Protestant 66-book canon.
     */
    fun getSeptuagintOnlyBooks(): List<BibleBook> {
        return BOOKS.filter { it.textTradition == TextTradition.Septuagint }
    }

    /**
     * Get books unique to Ethiopic tradition.
     *
     * These are books that exist ONLY in Ethiopian canon —
     * completely unknown to most Western readers due to
     * Protestant-Catholic cultural dominance.
     */
    fun getEthiopicOnlyBooks(): List<BibleBook> {
        return BOOKS.filter { it.textTradition == TextTradition.Ethiopic }
    }

    /**
     * Get books that are in ALL canons (universal books).
     *
     * These are the books no one disputes: the core biblical corpus
     * that exists across Protestant, Catholic, Orthodox, and Ethiopian
     * traditions.
     */
    fun getUniversalBooks(): List<BibleBook> {
        return BOOKS.filter { it.canons.size == 4 }  // All 4 canons
    }

    /**
     * Get books missing from Protestant canon.
     *
     * Returns books that exist in Catholic/Orthodox/Ethiopian but
     * NOT in Protestant — the "apocrypha" that Protestantism
     * removed from Bibles.
     */
    fun getMissingFromProtestant(): List<BibleBook> {
        return BOOKS.filter {
            com.bytecats.metanoia.models.Canon.Protestant !in it.canons
        }
    }

    /**
     * Get books exclusive to each canon.
     *
     * Shows what each tradition has that others don't:
     * - Protestant: nothing (it's a subset)
     * - Catholic: deuterocanonical (Tobit, Judith, Wisdom, etc.)
     * - Orthodox: adds 1-4 Maccabees, Prayer of Manasseh, Psalm 151
     * - Ethiopian: adds Enoch, Jubilees, Meqabyan, church books
     */
    fun getCanonExclusiveBooks(): Map<com.bytecats.metanoia.models.Canon, List<BibleBook>> {
        val exclusives = mutableMapOf<com.bytecats.metanoia.models.Canon, MutableList<BibleBook>>()

        BOOKS.forEach { book ->
            val exclusiveCanon = when {
                book.canons == setOf(com.bytecats.metanoia.models.Canon.Protestant) -> null  // Not exclusive
                book.canons == setOf(com.bytecats.metanoia.models.Canon.Catholic) -> com.bytecats.metanoia.models.Canon.Catholic
                book.canons == setOf(com.bytecats.metanoia.models.Canon.Orthodox) -> com.bytecats.metanoia.models.Canon.Orthodox
                book.canons == setOf(com.bytecats.metanoia.models.Canon.Ethiopian) -> com.bytecats.metanoia.models.Canon.Ethiopian
                else -> null  // Shared by multiple canons
            }
            if (exclusiveCanon != null) {
                exclusives.getOrPut(exclusiveCanon) { mutableListOf() }.add(book)
            }
        }

        return exclusives
    }

    /**
     * Search by verse content across ALL books.
     *
     * NOTE: This requires actual verse text in the database.
     * The query searches the `verses` table with NO canonical filtering.
     */
    suspend fun searchVersesEverywhere(
        bibleManager: BibleManager,
        query: String,
        limit: Int = 50
    ): List<com.bytecats.metanoia.models.SearchResult> {
        return bibleManager.searchVerses(query)  // BibleManager.searchVerses already searches everything
    }

    /**
     * Get summary statistics for the complete biblical corpus.
     *
     * Returns counts by tradition, canon, and section.
     */
    fun getCorpusStatistics(): CorpusStatistics {
        val byTradition = getAllBooksByTradition()
        val byCanon = BOOKS.groupBy { it.canons.size }
        val bySection = BOOKS.groupBy { it.section }

        return CorpusStatistics(
            totalBooks = BOOKS.size,
            byTradition = mapOf(
                TextTradition.Masoretic to (byTradition[TextTradition.Masoretic]?.size ?: 0),
                TextTradition.Septuagint to (byTradition[TextTradition.Septuagint]?.size ?: 0),
                TextTradition.NewTestament to (byTradition[TextTradition.NewTestament]?.size ?: 0),
                TextTradition.Ethiopic to (byTradition[TextTradition.Ethiopic]?.size ?: 0)
            ),
            byCanon = mapOf(
                "Protestant Only" to (byCanon[1]?.size ?: 0),
                "2 Canons" to (byCanon[2]?.size ?: 0),
                "3 Canons" to (byCanon[3]?.size ?: 0),
                "Universal (All 4)" to (byCanon[4]?.size ?: 0)
            ),
            missingFromProtestant = getMissingFromProtestant().size,
            ethiopianExclusive = getEthiopicOnlyBooks().size,
            bySection = bySection.mapKeys { it.key.name }.mapValues { it.value.size }
        )
    }
}

/**
 * Statistics about the complete biblical corpus.
 */
data class CorpusStatistics(
    val totalBooks: Int,
    val byTradition: Map<TextTradition, Int>,
    val byCanon: Map<String, Int>,
    val missingFromProtestant: Int,
    val ethiopianExclusive: Int,
    val bySection: Map<String, Int>
)

/**
 * Filter books by textual tradition.
 *
 * Usage:
 * - BOOKS.byTradition(TextTradition.Masoretic)    // Hebrew OT (39 books)
 * - BOOKS.byTradition(TextTradition.Septuagint)   // Greek OT + Deuterocanonical
 * - BOOKS.byTradition(TextTradition.NewTestament) // Greek NT (27 books)
 * - BOOKS.byTradition(TextTradition.Ethiopic)     // Ge'ez books
 */
fun List<com.bytecats.metanoia.models.BibleBook>.byTradition(tradition: TextTradition): List<com.bytecats.metanoia.models.BibleBook> {
    return filter { it.textTradition == tradition }
}

/**
 * Filter books that are universal (in all canons).
 */
fun List<com.bytecats.metanoia.models.BibleBook>.universalOnly(): List<com.bytecats.metanoia.models.BibleBook> {
    return filter { it.canons.size == 4 }
}

/**
 * Filter books exclusive to one canon.
 */
fun List<com.bytecats.metanoia.models.BibleBook>.exclusiveToCanon(canon: com.bytecats.metanoia.models.Canon): List<com.bytecats.metanoia.models.BibleBook> {
    return filter { it.canons == setOf(canon) }
}

/**
 * Filter books NOT in Protestant canon (the "missing" books).
 */
fun List<com.bytecats.metanoia.models.BibleBook>.notInProtestant(): List<com.bytecats.metanoia.models.BibleBook> {
    return filter { com.bytecats.metanoia.models.Canon.Protestant !in it.canons }
}