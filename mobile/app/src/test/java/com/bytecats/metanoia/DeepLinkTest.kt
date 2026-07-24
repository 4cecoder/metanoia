package com.bytecats.metanoia

import com.bytecats.metanoia.bible.DeepLink
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DeepLinkTest {

    // -------------------------------------------------------------------
    // Custom scheme: metanoia://bible/<book>/<chapter>[/<verse>]
    // -------------------------------------------------------------------

    @Test
    fun customScheme_bookChapterVerse() {
        val ref = DeepLink.parseParts("metanoia", "bible", listOf("John", "3", "16"))
        assertEquals("John", ref!!.book)
        assertEquals(3, ref.chapter)
        assertEquals(16, ref.verse)
    }

    @Test
    fun customScheme_bookChapterOnly_verseIsNull() {
        val ref = DeepLink.parseParts("metanoia", "bible", listOf("John", "3"))
        assertEquals("John", ref!!.book)
        assertEquals(3, ref.chapter)
        assertNull(ref.verse)
    }

    @Test
    fun customScheme_caseInsensitiveBookName() {
        val ref = DeepLink.parseParts("METANOIA", "BIBLE", listOf("john", "3", "16"))
        assertEquals("John", ref!!.book)
    }

    @Test
    fun customScheme_wrongHost_returnsNull() {
        assertNull(DeepLink.parseParts("metanoia", "verse", listOf("John", "3", "16")))
    }

    // -------------------------------------------------------------------
    // HTTPS App Link: https://<any-host>/bible/<book>/<chapter>[/<verse>]
    // -------------------------------------------------------------------

    @Test
    fun httpsScheme_bookChapterVerse() {
        val ref = DeepLink.parseParts("https", "metanoia.bytecats.codes", listOf("bible", "John", "3", "16"))
        assertEquals("John", ref!!.book)
        assertEquals(3, ref.chapter)
        assertEquals(16, ref.verse)
    }

    @Test
    fun httpScheme_alsoAccepted() {
        val ref = DeepLink.parseParts("http", "example.com", listOf("bible", "John", "3", "16"))
        assertEquals("John", ref!!.book)
    }

    @Test
    fun httpsScheme_hostIsNotChecked_anyHostWorks() {
        // Deliberate: verifying the *actual* App Links host is Android's own
        // job at install-verification time, not this parser's — see
        // DeepLink.kt's class doc and docs/ANDROID_DEEP_LINKS.md.
        val ref = DeepLink.parseParts("https", "some-random-unrelated-domain.example", listOf("bible", "John", "3", "16"))
        assertEquals("John", ref!!.book)
    }

    @Test
    fun httpsScheme_missingBiblePrefix_returnsNull() {
        assertNull(DeepLink.parseParts("https", "metanoia.bytecats.codes", listOf("John", "3", "16")))
    }

    // -------------------------------------------------------------------
    // Book resolution: canonical names, abbreviations, case, numeric prefixes
    // -------------------------------------------------------------------

    @Test
    fun bookResolution_numericPrefixCanonicalName() {
        val ref = DeepLink.parseParts("metanoia", "bible", listOf("1Samuel", "1", "1"))
        assertEquals("1Samuel", ref!!.book)
    }

    @Test
    fun bookResolution_noSpaceCanonicalName() {
        val ref = DeepLink.parseParts("metanoia", "bible", listOf("SongofSolomon", "1", "1"))
        assertEquals("SongofSolomon", ref!!.book)
    }

    @Test
    fun bookResolution_abbreviationFallback() {
        val ref = DeepLink.parseParts("metanoia", "bible", listOf("jn", "3", "16"))
        assertEquals("John", ref!!.book)
    }

    @Test
    fun bookResolution_numericAbbreviation() {
        val ref = DeepLink.parseParts("metanoia", "bible", listOf("1sam", "1", "1"))
        assertEquals("1Samuel", ref!!.book)
    }

    @Test
    fun bookResolution_unknownBook_returnsNull() {
        assertNull(DeepLink.parseParts("metanoia", "bible", listOf("NotARealBook", "1", "1")))
    }

    // -------------------------------------------------------------------
    // Chapter/verse validation
    // -------------------------------------------------------------------

    @Test
    fun chapter_outOfRange_returnsNull() {
        // John has 21 chapters.
        assertNull(DeepLink.parseParts("metanoia", "bible", listOf("John", "22")))
    }

    @Test
    fun chapter_zero_returnsNull() {
        assertNull(DeepLink.parseParts("metanoia", "bible", listOf("John", "0")))
    }

    @Test
    fun chapter_nonNumeric_returnsNull() {
        assertNull(DeepLink.parseParts("metanoia", "bible", listOf("John", "three")))
    }

    @Test
    fun verse_nonNumericWhenPresent_returnsNull() {
        assertNull(DeepLink.parseParts("metanoia", "bible", listOf("John", "3", "sixteen")))
    }

    @Test
    fun verse_zero_returnsNull() {
        assertNull(DeepLink.parseParts("metanoia", "bible", listOf("John", "3", "0")))
    }

    // -------------------------------------------------------------------
    // Malformed input
    // -------------------------------------------------------------------

    @Test
    fun missingChapter_returnsNull() {
        assertNull(DeepLink.parseParts("metanoia", "bible", listOf("John")))
    }

    @Test
    fun emptyPath_returnsNull() {
        assertNull(DeepLink.parseParts("metanoia", "bible", emptyList()))
    }

    @Test
    fun unrelatedScheme_returnsNull() {
        assertNull(DeepLink.parseParts("ftp", "bible", listOf("John", "3", "16")))
    }

    @Test
    fun nullSchemeOrHost_returnsNull() {
        assertNull(DeepLink.parseParts(null, "bible", listOf("John", "3", "16")))
        assertNull(DeepLink.parseParts("metanoia", null, listOf("John", "3", "16")))
    }
}
