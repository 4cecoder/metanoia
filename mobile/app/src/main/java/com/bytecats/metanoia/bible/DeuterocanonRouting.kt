package com.bytecats.metanoia.bible

/**
 * Routing data for the 18 deuterocanonical/Ethiopian-canon books
 * (models/BibleConstants.kt's BOOKS entries tagged "Eth", plus the 10 OT
 * deuterocanonical books) that have zero verse text in the shipped
 * data/bible.db and no BibleGateway page (see docs/MAINTENANCE.md's
 * "Deuterocanonical/Ethiopian" note and src/bible_db.zig's
 * `books_with_no_verse_text`).
 *
 * Kept as plain data (no Context/network dependency) so it's directly unit
 * testable and so BibleManager.fetchChapter/scrapeChapter can consult it
 * without duplicating the book list inline.
 *
 * Of these 18: WikisourceApocryphaScraper.SUPPORTED_BOOKS (Tobit, Judith,
 * Wisdom, Sirach) and WikisourceEnochScraper.BOOK_NAME (Enoch) now have a
 * real working scraper. The remaining 13 below were researched (see the
 * scraper task's final report for what was checked and why each didn't pan
 * out — mostly: no free/public-domain English translation exists online at
 * all, or the only one found was not viable — for example 1/2/3 Meqabyan's
 * one known complete English rendering is a self-published amateur
 * translation in a non-standard "Iyaric"/Jamaican-Patois-style dialect from
 * a c.2003 personal homepage, not a standard-register scholarly text
 * suitable for shipping as this app's Bible text) and have no scraper.
 * Fetching one of these should surface a clear, honest "no source
 * available" signal instead of either silently retrying forever or looking
 * identical to an ordinary network failure.
 */
object DeuterocanonRouting {
    val NO_SOURCE_BOOKS: Set<String> = setOf(
        "Jubilees",
        "1Meqabyan", "2Meqabyan", "3Meqabyan",
        "Tegsas",
        "SirateTsion", "Tizaz", "Gitsiw", "Abtilis",
        "1Dominos", "2Dominos", "Qalementos", "Didasqalia"
    )

    fun noSourceMessage(book: String): String =
        "No source available for $book: this book has no known, freely accessible English translation online."
}
