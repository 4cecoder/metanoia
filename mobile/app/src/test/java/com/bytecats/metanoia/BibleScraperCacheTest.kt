package com.bytecats.metanoia

import com.bytecats.metanoia.bible.BibleScraper
import kotlinx.coroutines.runBlocking
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Timeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException

class BibleScraperCacheTest {

    @get:Rule
    val tempDir = TemporaryFolder()

    private class CountingCall(private val req: Request, private val body: String) : Call {
        override fun request(): Request = req
        override fun execute(): Response = Response.Builder()
            .request(req)
            .protocol(okhttp3.Protocol.HTTP_1_1)
            .code(200)
            .message("OK")
            .body(body.toResponseBody("text/html".toMediaType()))
            .build()
        override fun enqueue(responseCallback: Callback) =
            responseCallback.onResponse(this, execute())
        override fun cancel() {}
        override fun isExecuted(): Boolean = false
        override fun isCanceled(): Boolean = false
        override fun timeout(): Timeout = Timeout.NONE
        override fun clone(): Call = this
    }

    private class CountingClient(private val body: String) : Call.Factory {
        var calls = 0
        override fun newCall(request: Request): Call {
            calls++
            return CountingCall(request, body)
        }
    }

    private val sampleHtml = """
        <html><body>
        <table class="tablefloat"><tr><td>
          <span class="reftop">1</span>
          <span class="greek">Παῦλος</span>
          <span class="pos">G1234</span>
          <span class="eng">Paul</span>
        </td></tr></table>
        </body></html>
    """.trimIndent()

    @Test
    fun cachedSnapshotAvoidsNetworkOnSecondCall() {
        val cacheDir = tempDir.newFolder("scraper_cache")
        val client = CountingClient(sampleHtml)
        val scraper = BibleScraper(client = client, cacheDir = cacheDir)

        var words1 = 0
        runBlocking { scraper.scrapeInterlinear("Genesis", 1) { _, _, _, _, _ -> words1++ } }
        assertEquals("first call should hit network", 1, client.calls)
        assertTrue("first call should parse words", words1 >= 1)

        var words2 = 0
        runBlocking { scraper.scrapeInterlinear("Genesis", 1) { _, _, _, _, _ -> words2++ } }
        assertEquals("second call should use cache", 1, client.calls)
        assertTrue("second call should still parse words", words2 >= 1)
    }

    @Test
    fun differentChaptersHitNetworkSeparately() {
        val cacheDir = tempDir.newFolder("scraper_cache")
        val client = CountingClient(sampleHtml)
        val scraper = BibleScraper(client = client, cacheDir = cacheDir)

        runBlocking { scraper.scrapeInterlinear("Genesis", 1) { _, _, _, _, _ -> } }
        runBlocking { scraper.scrapeInterlinear("Genesis", 2) { _, _, _, _, _ -> } }
        assertEquals("two different chapters = two network calls", 2, client.calls)
    }

    @Test
    fun retryEventuallySucceedsAfterTransientFailures() {
        val cacheDir = tempDir.newFolder("scraper_cache")

        class FlakyClient(private val body: String) : Call.Factory {
            var calls = 0
            override fun newCall(request: Request): Call {
                calls++
                val callNumber = calls
                return object : Call {
                    override fun request(): Request = request
                    override fun execute(): Response {
                        if (callNumber < 2) throw IOException("simulated transient failure")
                        return Response.Builder()
                            .request(request)
                            .protocol(okhttp3.Protocol.HTTP_1_1)
                            .code(200)
                            .message("OK")
                            .body(body.toResponseBody("text/html".toMediaType()))
                            .build()
                    }
                    override fun enqueue(responseCallback: Callback) =
                        responseCallback.onResponse(this, execute())
                    override fun cancel() {}
                    override fun isExecuted(): Boolean = false
                    override fun isCanceled(): Boolean = false
                    override fun timeout(): Timeout = Timeout.NONE
                    override fun clone(): Call = this
                }
            }
        }

        val client = FlakyClient(sampleHtml)
        val scraper = BibleScraper(client = client, cacheDir = cacheDir)
        var words = 0
        runBlocking { scraper.scrapeInterlinear("Genesis", 1) { _, _, _, _, _ -> words++ } }
        assertEquals("should retry after transient failure", 2, client.calls)
        assertTrue("should eventually parse words", words >= 1)
    }

    @Test
    fun allRetriesExhaustedThrowsIOException() {
        val cacheDir = tempDir.newFolder("scraper_cache")
        val client = object : Call.Factory {
            var calls = 0
            override fun newCall(request: Request): Call {
                calls++
                return object : Call {
                    override fun request(): Request = request
                    override fun execute(): Response = throw IOException("simulated failure")
                    override fun enqueue(responseCallback: Callback) =
                        responseCallback.onFailure(this, IOException("simulated failure"))
                    override fun cancel() {}
                    override fun isExecuted(): Boolean = false
                    override fun isCanceled(): Boolean = false
                    override fun timeout(): Timeout = Timeout.NONE
                    override fun clone(): Call = this
                }
            }
        }
        val scraper = BibleScraper(client = client, cacheDir = cacheDir, maxRetries = 3)
        var thrown: Throwable? = null
        runBlocking {
            try {
                scraper.scrapeInterlinear("Genesis", 1) { _, _, _, _, _ -> }
            } catch (e: Throwable) {
                thrown = e
            }
        }
        assertTrue("expected IOException after retries exhausted", thrown is IOException)
        assertEquals("should retry 3 times", 3, client.calls)
    }
}
