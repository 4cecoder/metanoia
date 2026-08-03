package com.bytecats.metanoia.bible

import kotlinx.coroutines.runBlocking
import java.io.IOException
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File

/**
 * Real unit tests for BibleGateway scraper using cached HTML.

 * These tests:
 * - Load actual HTML from test/resources/scraper_html/
 * - Use MockOkHttpClient to avoid network requests
 * - Test the ACTUAL Kotlin scraper parsing logic
 * - Validate verse extraction accuracy
 */
class BibleGatewayScraperTest {

    private lateinit var scraper: BibleGatewayScraper
    private lateinit var mockClient: MockOkHttpClient

    @Before
    fun setup() {
        // Load cached HTML from test resources
        val cachedResponses = mutableMapOf<String, String>()

        // Load Genesis 1 NKJV
        val genesisHtml = loadTestHtml("biblegateway_Genesis_1_NKJV.html")
        cachedResponses["https://www.biblegateway.com/passage/?search=Genesis+1&version=NKJV&interface=print"] = genesisHtml

        // Load Psalms 23 NKJV
        val psalmsHtml = loadTestHtml("biblegateway_Psalms_23_NKJV.html")
        cachedResponses["https://www.biblegateway.com/passage/?search=Psalms+23&version=NKJV&interface=print"] = psalmsHtml

        // Load Isaiah 53 NKJV
        val isaiahHtml = loadTestHtml("biblegateway_Isaiah_53_NKJV.html")
        cachedResponses["https://www.biblegateway.com/passage/?search=Isaiah+53&version=NKJV&interface=print"] = isaiahHtml

        // Load Matthew 1 NKJV
        val matthewHtml = loadTestHtml("biblegateway_Matthew_1_NKJV.html")
        cachedResponses["https://www.biblegateway.com/passage/?search=Matthew+1&version=NKJV&interface=print"] = matthewHtml

        // Load John 3 NKJV
        val johnHtml = loadTestHtml("biblegateway_John_3_NKJV.html")
        cachedResponses["https://www.biblegateway.com/passage/?search=John+3&version=NKJV&interface=print"] = johnHtml

        // Load Romans 8 NKJV
        val romansHtml = loadTestHtml("biblegateway_Romans_8_NKJV.html")
        cachedResponses["https://www.biblegateway.com/passage/?search=Romans+8&version=NKJV&interface=print"] = romansHtml

        mockClient = MockOkHttpClient(cachedResponses)
        scraper = BibleGatewayScraper(client = mockClient)
    }

    @Test
    fun `Genesis 1 extracts 31 verses`() = runBlocking {
        val verses = mutableListOf<Pair<Int, String>>()

        scraper.scrapeChapter("Genesis", 1, "NKJV") { verseNum, text ->
            verses.add(Pair(verseNum, text))
        }

        assertEquals("Genesis 1 should have 31 verses", 31, verses.size)
        assertEquals("First verse should be 1", 1, verses[0].first)
        assertEquals("Last verse should be 31", 31, verses.last().first)

        // Check that all verse numbers are sequential
        verses.forEachIndexed { index, (verseNum, _) ->
            assertEquals("Verse number should be sequential at index $index", index + 1, verseNum)
        }

        // Check first verse content
        assertTrue(
            "First verse should mention creation",
            verses[0].second.contains("beginning") ||
            verses[0].second.lowercase().contains("created")
        )

        // Check that verse text is not empty
        verses.forEach { (verseNum, text) ->
            assertTrue("Verse $verseNum should not be empty", text.isNotEmpty())
            assertTrue("Verse $verseNum should not be just whitespace", text.trim().isNotEmpty())
        }
    }

    @Test
    fun `Psalms 23 extracts verses correctly`() = runBlocking {
        val verses = mutableListOf<Pair<Int, String>>()

        scraper.scrapeChapter("Psalms", 23, "NKJV") { verseNum, text ->
            verses.add(Pair(verseNum, text))
        }

        assertTrue("Psalms 23 should have verses", verses.size >= 6)
        assertEquals("First verse should be 1", 1, verses[0].first)
        assertEquals("Last verse should be 6 or higher", 6, verses.last().first)

        // Check first verse content
        assertTrue(
            "First verse should mention the LORD or shepherd",
            verses[0].second.lowercase().contains("lord") ||
            verses[0].second.lowercase().contains("shepherd")
        )

        // Check that verse text is not empty
        verses.forEach { (verseNum, text) ->
            assertTrue("Verse $verseNum should not be empty", text.isNotEmpty())
        }
    }

    @Test
    fun `Isaiah 53 extracts verses correctly`() = runBlocking {
        val verses = mutableListOf<Pair<Int, String>>()

        scraper.scrapeChapter("Isaiah", 53, "NKJV") { verseNum, text ->
            verses.add(Pair(verseNum, text))
        }

        assertTrue("Isaiah 53 should have verses", verses.size >= 12)
        assertEquals("First verse should be 1", 1, verses[0].first)
        assertEquals("Last verse should be 12 or higher", 12, verses.last().first)
    }

    @Test
    fun `Matthew 1 extracts verses correctly`() = runBlocking {
        val verses = mutableListOf<Pair<Int, String>>()

        scraper.scrapeChapter("Matthew", 1, "NKJV") { verseNum, text ->
            verses.add(Pair(verseNum, text))
        }

        assertTrue("Matthew 1 should have verses", verses.size >= 25)
        assertEquals("First verse should be 1", 1, verses[0].first)
        assertEquals("Last verse should be 25 or higher", 25, verses.last().first)
    }

    @Test
    fun `John 3 extracts 36 verses`() = runBlocking {
        val verses = mutableListOf<Pair<Int, String>>()

        scraper.scrapeChapter("John", 3, "NKJV") { verseNum, text ->
            verses.add(Pair(verseNum, text))
        }

        assertEquals("John 3 should have 36 verses", 36, verses.size)
        assertEquals("First verse should be 1", 1, verses[0].first)
        assertEquals("Last verse should be 36", 36, verses.last().first)
    }

    @Test
    fun `Romans 8 extracts verses correctly`() = runBlocking {
        val verses = mutableListOf<Pair<Int, String>>()

        scraper.scrapeChapter("Romans", 8, "NKJV") { verseNum, text ->
            verses.add(Pair(verseNum, text))
        }

        assertTrue("Romans 8 should have verses", verses.size >= 39)
        assertEquals("First verse should be 1", 1, verses[0].first)
        assertEquals("Last verse should be 39 or higher", 39, verses.last().first)
    }

    @Test
    fun `Verse numbers are extracted correctly from class names`() = runBlocking {
        val verses = mutableListOf<Pair<Int, String>>()

        scraper.scrapeChapter("Genesis", 1, "NKJV") { verseNum, text ->
            verses.add(Pair(verseNum, text))
        }

        // Check specific verse numbers
        assertEquals("Verse 1 should be extracted correctly", 1, verses[0].first)
        assertEquals("Verse 10 should be extracted correctly", 10, verses[9].first)
        assertEquals("Verse 20 should be extracted correctly", 20, verses[19].first)
        assertEquals("Verse 31 should be extracted correctly", 31, verses[30].first)
    }

    @Test
    fun `Verse markers are removed from text`() = runBlocking {
        val verses = mutableListOf<Pair<Int, String>>()

        scraper.scrapeChapter("Genesis", 1, "NKJV") { verseNum, text ->
            verses.add(Pair(verseNum, text))
        }

        // Check that verse numbers don't appear in the text
        verses.forEach { (verseNum, text) ->
            // The verse number should NOT be at the start of the text
            // (it should be extracted from the class name, not the text)
            assertFalse(
                "Verse $verseNum should not have verse number at start of text: $text",
                text.trim().startsWith("$verseNum")
            )
        }
    }

    @Test
    fun `Returns correct base URL`() {
        assertEquals("www.biblegateway.com", scraper.getBaseUrl())
    }

    @Test
    fun `Returns correct priority`() {
        assertEquals(10, scraper.getPriority())
    }

    @Test
    fun `Supports standard books`() {
        assertTrue("Genesis should be supported", scraper.supportsBook("Genesis"))
        assertTrue("Psalms should be supported", scraper.supportsBook("Psalms"))
        assertTrue("Matthew should be supported", scraper.supportsBook("Matthew"))
        assertTrue("Romans should be supported", scraper.supportsBook("Romans"))
    }

    @Test
    fun `Does not support apocrypha books`() {
        assertFalse("Tobit should not be supported", scraper.supportsBook("Tobit"))
        assertFalse("Judith should not be supported", scraper.supportsBook("Judith"))
        assertFalse("Wisdom should not be supported", scraper.supportsBook("Wisdom"))
        assertFalse("Sirach should not be supported", scraper.supportsBook("Sirach"))
        assertFalse("Enoch should not be supported", scraper.supportsBook("Enoch"))
    }

    @Test
    fun `Does not support Ethiopian canon books`() {
        assertFalse("1Meqabyan should not be supported", scraper.supportsBook("1Meqabyan"))
        assertFalse("Jubilees should not be supported", scraper.supportsBook("Jubilees"))
        assertFalse("Didasqalia should not be supported", scraper.supportsBook("Didasqalia"))
    }

    /**
     * Load HTML file from test resources.
     */
    private fun loadTestHtml(filename: String): String {
        val classLoader = javaClass.classLoader
        val resource = classLoader.getResourceAsStream("scraper_html/$filename")
            ?: throw IOException("Test resource not found: scraper_html/$filename")

        return resource.bufferedReader().use { it.readText() }
    }
}