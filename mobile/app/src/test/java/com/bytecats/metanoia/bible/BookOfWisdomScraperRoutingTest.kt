package com.bytecats.metanoia.bible

import com.bytecats.metanoia.bible.DeuterocanonRouting
import com.bytecats.metanoia.bible.WikisourceApocryphaScraper
import kotlinx.coroutines.runBlocking
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Timeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException

/**
 * Test that Book of Wisdom routes correctly to WikisourceApocryphaScraper
 * and does not crash the app.
 *
 * Book of Wisdom is an apocryphal/deuterocanonical book that BibleGateway
 * and BibleHub do NOT support. The app must route it to Wikisource instead.
 */
class BookOfWisdomScraperRoutingTest {

    private class FailingCall(private val req: Request) : Call {
        override fun request(): Request = req
        override fun execute(): Response = throw IOException("simulated network failure")
        override fun enqueue(responseCallback: Callback) =
            responseCallback.onFailure(this, IOException("simulated network failure"))
        override fun cancel() {}
        override fun isExecuted(): Boolean = false
        override fun isCanceled(): Boolean = false
        override fun timeout(): Timeout = Timeout.NONE
        override fun clone(): Call = this
    }

    private class FixedBodyCall(private val req: Request, private val html: String?, private val code: Int = 200) : Call {
        override fun request(): Request = req
        override fun execute(): Response {
            val builder = Response.Builder()
                .request(req)
                .protocol(Protocol.HTTP_1_1)
                .code(code)
                .message(if (code in 200..299) "OK" else "Error")
                .body((html ?: "").toResponseBody("text/html".toMediaType()))
            return builder.build()
        }
        override fun enqueue(responseCallback: Callback) = responseCallback.onResponse(this, execute())
        override fun cancel() {}
        override fun isExecuted(): Boolean = false
        override fun isCanceled(): Boolean = false
        override fun timeout(): Timeout = Timeout.NONE
        override fun clone(): Call = this
    }

    private val wisdomFixtureHtml = """
        <div id="mw-content-text"><div class="mw-parser-output">
        <section class="mf-section-1"><h2 id="Chapter_1">Chapter 1</h2>
        <p><span id="chapter_1" class="wst-anchor"></span>
        </p><p><span class="wst-verse wst-verse-default" id="1:1"><sup>1</sup></span> Love righteousness, ye that be judges of the earth: think of the Lord with a good (heart,) and in simplicity of heart seek him.
        </p><p><span class="wst-verse wst-verse-default" id="1:2"><sup>2</sup></span> For he will be found of them that tempt him not; and sheweth himself unto such as do not distrust him.
        </p><p><span class="wst-verse wst-verse-default" id="1:3"><sup>3</sup></span> For froward thoughts separate from God: and his power, when it is tried, reproveth the unwise.
        </p></section></div></div>
    """.trimIndent()

    @Test
    fun wisdomIsInSupportedBooks() {
        assertTrue("Wisdom should be in WikisourceApocryphaScraper.SUPPORTED_BOOKS",
            "Wisdom" in WikisourceApocryphaScraper.SUPPORTED_BOOKS)
    }

    @Test
    fun wisdomIsNotInNoSourceBooks() {
        assertTrue("Wisdom should NOT be in DeuterocanonRouting.NO_SOURCE_BOOKS (it has a scraper)",
            "Wisdom" !in DeuterocanonRouting.NO_SOURCE_BOOKS)
    }

    @Test
    fun scraperCanParseWisdomVerseMarkup() {
        val client = Call.Factory { request -> FixedBodyCall(request, wisdomFixtureHtml) }
        val scraper = WikisourceApocryphaScraper(client = client)
        val verses = mutableListOf<Pair<Int, String>>()
        runBlocking {
            scraper.scrapeChapter("Wisdom", 1) { num, text -> verses.add(num to text) }
        }
        assertEquals("Should have parsed 3 verses", 3, verses.size)
        assertEquals(1, verses[0].first)
        assertTrue(verses[0].second.contains("Love righteousness"))
        assertEquals(2, verses[1].first)
        assertTrue(verses[1].second.contains("tempt him not"))
        assertEquals(3, verses[2].first)
        assertTrue(verses[2].second.contains("froward thoughts"))
    }

    @Test
    fun scraperThrowsOnUnsupportedBook() {
        val client = Call.Factory { request -> FixedBodyCall(request, wisdomFixtureHtml) }
        val scraper = WikisourceApocryphaScraper(client = client)
        try {
            runBlocking { scraper.scrapeChapter("Genesis", 1) { _, _ -> } }
            fail("Should have thrown IllegalArgumentException for unsupported book")
        } catch (e: IllegalArgumentException) {
            assertTrue("Error message should mention the book", e.message?.contains("Genesis") == true)
        }
    }

    @Test
    fun scraperPropagatesNetworkFailureInsteadOfSwallowing() {
        val failingClient = Call.Factory { request -> FailingCall(request) }
        val scraper = WikisourceApocryphaScraper(client = failingClient)
        var callbackInvoked = false
        try {
            runBlocking { scraper.scrapeChapter("Wisdom", 1) { _, _ -> callbackInvoked = true } }
            fail("Should have thrown IOException for network failure")
        } catch (e: IOException) {
            assertTrue("Should have propagated network failure", e.message?.contains("network") == true)
        }
        assertFalse("onVerse should never fire when fetch fails", callbackInvoked)
    }

    @Test
    fun allFourApocryphalBooksAreCovered() {
        assertEquals(setOf("Tobit", "Judith", "Wisdom", "Sirach"), WikisourceApocryphaScraper.SUPPORTED_BOOKS)
    }
}