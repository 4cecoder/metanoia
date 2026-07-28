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
import org.junit.Test
import java.io.File

/**
 * Regression tests that exercise the scraper parser against real cached
 * BibleHub HTML snapshots. These tests never touch the network.
 */
class BibleScraperSnapshotParseTest {

    private class FixtureCall(private val req: Request, private val body: String) : Call {
        override fun request(): Request = req
        override fun execute(): Response = Response.Builder()
            .request(req)
            .protocol(okhttp3.Protocol.HTTP_1_1)
            .code(200)
            .message("OK")
            .body(body.toResponseBody("text/html".toMediaType()))
            .build()
        override fun enqueue(responseCallback: Callback) = responseCallback.onResponse(this, execute())
        override fun cancel() {}
        override fun isExecuted(): Boolean = false
        override fun isCanceled(): Boolean = false
        override fun timeout(): Timeout = Timeout.NONE
        override fun clone(): Call = this
    }

    private class FixtureClient(private val body: String) : Call.Factory {
        override fun newCall(request: Request): Call = FixtureCall(request, body)
    }

    private fun loadFixture(name: String): String {
        return javaClass.classLoader!!.getResourceAsStream("biblehub/$name")
            ?.bufferedReader()
            ?.use { it.readText() }
            ?: throw IllegalStateException("Missing test fixture: biblehub/$name")
    }

    @Test
    fun genesis1ParsesAll31Verses() {
        val scraper = BibleScraper(client = FixtureClient(loadFixture("genesis_1.html")))
        val wordsByVerse = mutableMapOf<Int, Int>()
        runBlocking {
            scraper.scrapeInterlinear("Genesis", 1) { v, _, _, _, _ ->
                wordsByVerse[v] = wordsByVerse.getOrDefault(v, 0) + 1
            }
        }
        assertEquals(31, wordsByVerse.size)
        assertTrue("Genesis 1:1 should have words", (wordsByVerse[1] ?: 0) > 0)
        assertTrue("Genesis 1:31 should have words", (wordsByVerse[31] ?: 0) > 0)
    }

    @Test
    fun firstCorinthians1ParsesAll31Verses() {
        val scraper = BibleScraper(client = FixtureClient(loadFixture("1_corinthians_1.html")))
        val wordsByVerse = mutableMapOf<Int, Int>()
        runBlocking {
            scraper.scrapeInterlinear("1Corinthians", 1) { v, _, _, _, _ ->
                wordsByVerse[v] = wordsByVerse.getOrDefault(v, 0) + 1
            }
        }
        assertEquals(31, wordsByVerse.size)
        assertTrue("1 Corinthians 1:1 should have words", (wordsByVerse[1] ?: 0) > 0)
        assertTrue("1 Corinthians 1:31 should have words", (wordsByVerse[31] ?: 0) > 0)
    }

    @Test
    fun interlinearWordsIncludeOriginalTextAndStrongs() {
        val scraper = BibleScraper(client = FixtureClient(loadFixture("1_corinthians_1.html")))
        val words = mutableListOf<Triple<Int, String, String>>()
        runBlocking {
            scraper.scrapeInterlinear("1Corinthians", 1) { v, _, orig, _, strongs ->
                words.add(Triple(v, orig, strongs))
            }
        }
        val firstWord = words.first()
        assertEquals(1, firstWord.first)
        assertTrue("First word should be Greek", firstWord.second.isNotEmpty())
        assertTrue("First word should have a Strong's number", firstWord.third.startsWith("G"))
    }
}
