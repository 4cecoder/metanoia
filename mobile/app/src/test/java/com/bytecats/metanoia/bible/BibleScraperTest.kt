package com.bytecats.metanoia.bible

import com.bytecats.metanoia.bible.BibleScraper
import kotlinx.coroutines.runBlocking
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Request
import okhttp3.Response
import okio.Timeout
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

/**
 * Regression coverage for the "silently swallowed fetch failure" bug class:
 * BibleScraper used to catch every network/parse exception internally and
 * just Log.e it, so a failed fetch looked exactly like "still loading"
 * forever, with no error surfaced and no retry signal — mirroring the bare
 * `except:` (Python) / `catch {}` (Zig) bug already found and fixed
 * elsewhere in this codebase. These tests assert that failures now
 * propagate out of BibleScraper instead of vanishing.
 *
 * Uses a hand-written fake okhttp3.Call.Factory (rather than a class-mocking
 * framework) so the test doesn't depend on real network access or on
 * bytecode-instrumentation-based mocking of OkHttp's concrete classes.
 */
class BibleScraperTest {

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

    /** A Call.Factory whose calls always fail with a simulated network error. */
    private val failingClient = Call.Factory { request -> FailingCall(request) }

    @Test
    fun scrapeChapterSurfacesNetworkFailureInsteadOfSwallowingIt() {
        val scraper = BibleScraper(client = failingClient)
        var callbackInvoked = false
        var thrown: Throwable? = null
        runBlocking {
            try {
                scraper.scrapeChapter("Genesis", 1) { _, _ -> callbackInvoked = true }
            } catch (e: Throwable) {
                thrown = e
            }
        }
        assertTrue("Expected scrapeChapter to propagate the failure, not swallow it", thrown is IOException)
        assertFalse("onVerse should never fire when the fetch failed", callbackInvoked)
    }

    @Test
    fun scrapeInterlinearSurfacesNetworkFailureInsteadOfSwallowingIt() {
        val scraper = BibleScraper(client = failingClient)
        var callbackInvoked = false
        var thrown: Throwable? = null
        runBlocking {
            try {
                scraper.scrapeInterlinear("Genesis", 1) { _, _, _, _, _ -> callbackInvoked = true }
            } catch (e: Throwable) {
                thrown = e
            }
        }
        assertTrue("Expected scrapeInterlinear to propagate the failure, not swallow it", thrown is IOException)
        assertFalse("onWord should never fire when the fetch failed", callbackInvoked)
    }

    @Test
    fun scrapeLexiconSurfacesNetworkFailureInsteadOfSwallowingIt() {
        val scraper = BibleScraper(client = failingClient)
        var callbackInvoked = false
        var thrown: Throwable? = null
        runBlocking {
            try {
                // "Genesis" is Old Testament, so this exercises the Hebrew lookup path.
                scraper.scrapeLexicon("H430", "Genesis") { _, _, _, _ -> callbackInvoked = true }
            } catch (e: Throwable) {
                thrown = e
            }
        }
        assertTrue("Expected scrapeLexicon to propagate the failure, not swallow it", thrown is IOException)
        assertFalse("onResult should never fire when the fetch failed", callbackInvoked)
    }
}
