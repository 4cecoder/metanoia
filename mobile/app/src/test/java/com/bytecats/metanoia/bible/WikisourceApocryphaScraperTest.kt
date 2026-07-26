package com.bytecats.metanoia.bible

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
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

/**
 * Tests for WikisourceApocryphaScraper (Tobit/Judith/Wisdom/Sirach), the
 * new scraper built for the four deuterocanonical books that have real,
 * publicly-hosted KJV Apocrypha text on Wikisource but no BibleGateway page.
 *
 * The success-path fixture below is a trimmed, verbatim excerpt of the real
 * HTML fetched from https://en.wikisource.org/wiki/Bible_(King_James)/Tobit
 * during development (chapter 1 verses 1-3 plus 22, and chapter 2 verse 1,
 * to exercise both ordinary parsing and chapter-boundary filtering) — not
 * guessed markup. Unlike BibleScraperTest (which only covers failure
 * propagation), this also covers the success-parsing path.
 */
class WikisourceApocryphaScraperTest {

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

    // Trimmed, verbatim excerpt of the real Wikisource "Bible (King James)/Tobit"
    // page HTML (fetched 2026-07-22): chapter 1 verses 1-3 and 22, chapter 2 verse 1.
    private val tobitFixtureHtml = """
        <div id="mw-content-text"><div class="mw-parser-output">
        <section class="mf-section-1"><h2 id="Chapter_1">Chapter 1</h2>
        <p><span id="chapter_1" class="wst-anchor"></span>
        </p><p><span class="wst-verse wst-verse-default" id="1:1"><sup>1</sup></span> The book of the words of Tobit, son of Tobiel, the son of Ananiel, the son of Aduel, the son of Gabael, of the seed of Asael, of the tribe of Nephthali;
        </p><p><span class="wst-verse wst-verse-default" id="1:2"><sup>2</sup></span> Who in the time of Enemessar king of the Assyrians was led captive out of Thisbe, which is at the right hand of that city, which is called properly Nephthali in Galilee above Aser.
        </p><p><span class="wst-verse wst-verse-default" id="1:3"><sup>3</sup></span> I Tobit have walked all the days of my life in the way of truth and justice, and I did many almsdeeds to my brethren, and my nation, who came with me to Nineve, into the land of the Assyrians.
        </p><p><span class="wst-verse wst-verse-default" id="1:22"><sup>22</sup></span> And Achiacharus intreating for me, I returned to Nineve. Now Achiacharus was cupbearer, and keeper of the signet, and steward, and overseer of the accounts: and Sarchedonus appointed him next unto him: and he was my brother's son.
        </p>
        </section><section class="mf-section-2"><h2 id="Chapter_2">Chapter 2</h2>
        <p><span id="chapter_2" class="wst-anchor"></span>
        </p><p><span class="wst-verse wst-verse-default" id="2:1"><sup>1</sup></span> Now when I was come home again, and my wife Anna was restored unto me, with my son Tobias, in the feast of Pentecost, which is the holy feast of the seven weeks, there was a good dinner prepared me, in the which I sat down to eat.
        </p>
        </section>
        </div></div>
    """.trimIndent()

    @Test
    fun scrapeChapterParsesRealVerseMarkupAndFiltersToRequestedChapter() {
        val client = Call.Factory { request -> FixedBodyCall(request, tobitFixtureHtml) }
        val scraper = WikisourceApocryphaScraper(client = client)
        val verses = mutableListOf<Pair<Int, String>>()
        runBlocking {
            scraper.scrapeChapter("Tobit", 1) { num, text -> verses.add(num to text) }
        }
        assertEquals(4, verses.size)
        assertEquals(1, verses[0].first)
        assertTrue(verses[0].second.startsWith("The book of the words of Tobit"))
        assertEquals(22, verses[3].first)
        assertTrue(verses[3].second.contains("Achiacharus"))
        // Chapter 2's verse must not leak into chapter 1's results.
        assertTrue(verses.none { it.second.contains("Pentecost") })
    }

    @Test
    fun scrapeChapterOnlyReturnsRequestedChapterVerses() {
        val client = Call.Factory { request -> FixedBodyCall(request, tobitFixtureHtml) }
        val scraper = WikisourceApocryphaScraper(client = client)
        val verses = mutableListOf<Pair<Int, String>>()
        runBlocking {
            scraper.scrapeChapter("Tobit", 2) { num, text -> verses.add(num to text) }
        }
        assertEquals(1, verses.size)
        assertEquals(1, verses[0].first)
        assertTrue(verses[0].second.contains("Pentecost"))
    }

    @Test
    fun scrapeChapterRejectsUnsupportedBook() {
        val client = Call.Factory { request -> FixedBodyCall(request, tobitFixtureHtml) }
        val scraper = WikisourceApocryphaScraper(client = client)
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { scraper.scrapeChapter("Genesis", 1) { _, _ -> } }
        }
    }

    @Test
    fun scrapeChapterSurfacesNetworkFailureInsteadOfSwallowingIt() {
        val failingClient = Call.Factory { request -> FailingCall(request) }
        val scraper = WikisourceApocryphaScraper(client = failingClient)
        var callbackInvoked = false
        var thrown: Throwable? = null
        runBlocking {
            try {
                scraper.scrapeChapter("Tobit", 1) { _, _ -> callbackInvoked = true }
            } catch (e: Throwable) {
                thrown = e
            }
        }
        assertTrue("Expected scrapeChapter to propagate the failure, not swallow it", thrown is IOException)
        assertFalse("onVerse should never fire when the fetch failed", callbackInvoked)
    }

    @Test
    fun supportedBooksCoversAllFourDeuterocanonicalBooksThisScraperHandles() {
        assertEquals(setOf("Tobit", "Judith", "Wisdom", "Sirach"), WikisourceApocryphaScraper.SUPPORTED_BOOKS)
    }
}
