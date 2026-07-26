package com.bytecats.metanoia.bible

import com.bytecats.metanoia.bible.WikisourceEnochScraper
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
import org.junit.Test
import java.io.IOException

/**
 * Tests for WikisourceEnochScraper, the new scraper built for the Book of
 * Enoch (R.H. Charles' 1917 translation), which has no BibleGateway page.
 *
 * The success-path fixture is a trimmed, verbatim excerpt of the real HTML
 * fetched from
 * https://en.wikisource.org/wiki/The_Book_of_Enoch_(Charles)/Chapter_01
 * during development — not guessed markup. It deliberately keeps the messy
 * bits of the real page (a poetic line broken across several extra `<p>`
 * tags that don't start a new verse, and editorial "up-arrow" bracket
 * notation like "⌈⌈and⌉⌉") to prove the join-then-regex-split
 * approach documented in WikisourceEnochScraper's class doc survives them.
 */
class WikisourceEnochScraperTest {

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

    private class FixedBodyCall(private val req: Request, private val html: String?) : Call {
        override fun request(): Request = req
        override fun execute(): Response = Response.Builder()
            .request(req)
            .protocol(Protocol.HTTP_1_1)
            .code(200)
            .message("OK")
            .body((html ?: "").toResponseBody("text/html".toMediaType()))
            .build()
        override fun enqueue(responseCallback: Callback) = responseCallback.onResponse(this, execute())
        override fun cancel() {}
        override fun isExecuted(): Boolean = false
        override fun isCanceled(): Boolean = false
        override fun timeout(): Timeout = Timeout.NONE
        override fun clone(): Call = this
    }

    // Trimmed, verbatim excerpt of the real Wikisource
    // "The_Book_of_Enoch_(Charles)/Chapter_01" page HTML (fetched 2026-07-22).
    private val enochChapter1FixtureHtml = """
        <div id="mw-content-text"><div class="mw-parser-output">
        <section class="mf-section-3">
        <p>CHAPTER I.
        </p><p>1. The words of the blessing of Enoch, wherewith he blessed the elect &#8968;&#8968;and&#8969;&#8969; righteous, who will be living in the day of tribulation, when all the wicked &#8968;&#8968;and godless&#8969;&#8969; are to be removed. 2. And he took up his parable and said&#8212;Enoch a righteous man, whose eyes were opened by God, saw the vision of the Holy One in the heavens, &#8968;which&#8969; the angels showed me, and from them I heard everything, and from them I understood as I saw, but not for this generation, but for a remote one which is for to come. 3. Concerning the elect I said, and took up &#8968;my&#8969; parable concerning them:
        </p><p><br/>
        The Holy Great One will come forth from His dwelling,
        </p><p>4. And the eternal God will tread upon the earth, (even) on Mount Sinai,
        </p><p>[And appear from His camp]
        </p><p>And appear in the strength of His might from the heaven &#8968;of heavens&#8969;.
        </p><p><br/>
        5. And all shall be smitten with fear,
        </p><p>And the Watchers shall quake,
        </p><p>And great fear and trembling shall seize them unto the ends of the earth.
        </p>
        </section>
        </div></div>
    """.trimIndent()

    @Test
    fun scrapeChapterSplitsRealNumberedProseIntoVerses() {
        val client = Call.Factory { request -> FixedBodyCall(request, enochChapter1FixtureHtml) }
        val scraper = WikisourceEnochScraper(client = client)
        val verses = mutableListOf<Pair<Int, String>>()
        runBlocking {
            scraper.scrapeChapter(1) { num, text -> verses.add(num to text) }
        }
        assertEquals(listOf(1, 2, 3, 4, 5), verses.map { it.first })
        assertTrue(verses[0].second.startsWith("The words of the blessing of Enoch"))
        assertTrue(verses[1].second.startsWith("And he took up his parable"))
        // Verse 4's poetic continuation lines (split across several extra
        // <p> tags with no leading verse number) must fold into verse 4,
        // not get dropped or misattributed to verse 3 or 5.
        assertTrue(verses[3].second.contains("Mount Sinai"))
        assertTrue(verses[3].second.contains("appear from His camp"))
        assertTrue(verses[3].second.contains("heaven"))
        assertTrue(verses[4].second.startsWith("And all shall be smitten with fear"))
        assertTrue(verses[4].second.contains("Watchers shall quake"))
    }

    @Test
    fun scrapeChapterPadsChapterNumberInUrl() {
        var capturedUrl: String? = null
        val client = Call.Factory { request ->
            capturedUrl = request.url.toString()
            FixedBodyCall(request, enochChapter1FixtureHtml)
        }
        val scraper = WikisourceEnochScraper(client = client)
        runBlocking { scraper.scrapeChapter(7) { _, _ -> } }
        assertTrue("Expected zero-padded chapter number in URL, got $capturedUrl", capturedUrl!!.endsWith("Chapter_07"))
    }

    @Test
    fun scrapeChapterSurfacesNetworkFailureInsteadOfSwallowingIt() {
        val failingClient = Call.Factory { request -> FailingCall(request) }
        val scraper = WikisourceEnochScraper(client = failingClient)
        var callbackInvoked = false
        var thrown: Throwable? = null
        runBlocking {
            try {
                scraper.scrapeChapter(1) { _, _ -> callbackInvoked = true }
            } catch (e: Throwable) {
                thrown = e
            }
        }
        assertTrue("Expected scrapeChapter to propagate the failure, not swallow it", thrown is IOException)
        assertFalse("onVerse should never fire when the fetch failed", callbackInvoked)
    }
}
