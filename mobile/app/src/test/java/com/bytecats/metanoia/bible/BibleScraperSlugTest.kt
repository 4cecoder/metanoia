package com.bytecats.metanoia.bible

import com.bytecats.metanoia.bible.BibleScraper
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class BibleScraperSlugTest {

    private fun slugOf(book: String): String {
        // interlinearSlug is private; use reflection to test the mapping.
        val scraper = BibleScraper()
        val method = BibleScraper::class.java.getDeclaredMethod("interlinearSlug", String::class.java)
        method.isAccessible = true
        return method.invoke(scraper, book) as String
    }

    @Test
    fun numberedBooksGetUnderscore() {
        assertEquals("1_corinthians", slugOf("1Corinthians"))
        assertEquals("2_corinthians", slugOf("2Corinthians"))
        assertEquals("1_samuel", slugOf("1Samuel"))
        assertEquals("2_samuel", slugOf("2Samuel"))
        assertEquals("1_kings", slugOf("1Kings"))
        assertEquals("2_kings", slugOf("2Kings"))
        assertEquals("1_chronicles", slugOf("1Chronicles"))
        assertEquals("2_chronicles", slugOf("2Chronicles"))
        assertEquals("1_thessalonians", slugOf("1Thessalonians"))
        assertEquals("2_thessalonians", slugOf("2Thessalonians"))
        assertEquals("1_timothy", slugOf("1Timothy"))
        assertEquals("2_timothy", slugOf("2Timothy"))
        assertEquals("1_peter", slugOf("1Peter"))
        assertEquals("2_peter", slugOf("2Peter"))
        assertEquals("1_john", slugOf("1John"))
        assertEquals("2_john", slugOf("2John"))
        assertEquals("3_john", slugOf("3John"))
    }

    @Test
    fun unnumberedBooksStayPlain() {
        assertEquals("matthew", slugOf("Matthew"))
        assertEquals("mark", slugOf("Mark"))
        assertEquals("luke", slugOf("Luke"))
        assertEquals("john", slugOf("John"))
        assertEquals("acts", slugOf("Acts"))
        assertEquals("romans", slugOf("Romans"))
        assertEquals("galatians", slugOf("Galatians"))
        assertEquals("ephesians", slugOf("Ephesians"))
        assertEquals("philippians", slugOf("Philippians"))
        assertEquals("colossians", slugOf("Colossians"))
        assertEquals("titus", slugOf("Titus"))
        assertEquals("philemon", slugOf("Philemon"))
        assertEquals("hebrews", slugOf("Hebrews"))
        assertEquals("james", slugOf("James"))
        assertEquals("jude", slugOf("Jude"))
        assertEquals("revelation", slugOf("Revelation"))
        assertEquals("genesis", slugOf("Genesis"))
        assertEquals("psalms", slugOf("Psalms"))
    }

    @Test
    fun spacesRemoved() {
        assertEquals("1_corinthians", slugOf("1 Corinthians"))
        assertEquals("2_samuel", slugOf("2 Samuel"))
    }

    @Test
    fun songOfSolomonMapsToSongs() {
        assertEquals("songs", slugOf("Song of Solomon"))
        assertEquals("songs", slugOf("SongofSolomon"))
    }
}
