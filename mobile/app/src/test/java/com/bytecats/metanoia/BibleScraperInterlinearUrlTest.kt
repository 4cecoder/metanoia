package com.bytecats.metanoia

import com.bytecats.metanoia.bible.BibleScraper
import com.bytecats.metanoia.models.BOOKS
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
import java.io.IOException

/**
 * Regression coverage for the BibleHub interlinear URL slug bug.
 *
 * Uses real BibleHub HTML snapshots stored under test/resources/biblehub/ instead
 * of hitting the network. The tests intercept the request the scraper makes, assert
 * the exact URL, and return a cached HTML body so parsing is also exercised.
 */
class BibleScraperInterlinearUrlTest {

    private class FixtureClient(
        private val fixture: String,
        val urls: MutableList<String> = mutableListOf()
    ) : Call.Factory {
        override fun newCall(request: Request): Call {
            urls.add(request.url.toString())
            return FixtureCall(request, fixture)
        }
    }

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

    private class NotFoundClient : Call.Factory {
        override fun newCall(request: Request): Call {
            return object : Call {
                override fun request(): Request = request
                override fun execute(): Response = Response.Builder()
                    .request(request)
                    .protocol(okhttp3.Protocol.HTTP_1_1)
                    .code(404)
                    .message("Not Found")
                    .body("".toResponseBody("text/plain".toMediaType()))
                    .build()
                override fun enqueue(responseCallback: Callback) = responseCallback.onResponse(this, execute())
                override fun cancel() {}
                override fun isExecuted(): Boolean = false
                override fun isCanceled(): Boolean = false
                override fun timeout(): Timeout = Timeout.NONE
                override fun clone(): Call = this
            }
        }
    }

    private fun loadFixture(path: String): String {
        return javaClass.classLoader!!.getResourceAsStream(path)
            ?.bufferedReader()
            ?.use { it.readText() }
            ?: throw IllegalStateException("Missing test fixture: $path")
    }

    @Test
    fun scrapeInterlinearBuildsCorrectUrlForEveryBook() {
        val fixture = loadFixture("biblehub/1_corinthians_1.html")
        val client = FixtureClient(fixture)
        val scraper = BibleScraper(client = client)

        BOOKS.forEach { book ->
            client.urls.clear()
            var wordCount = 0
            var thrown: Throwable? = null
            runBlocking {
                try {
                    scraper.scrapeInterlinear(book.name, 1) { _, _, _, _, _ ->
                        wordCount++
                    }
                } catch (e: Throwable) {
                    thrown = e
                }
            }
            val expectedHost = "https://biblehub.com/interlinear/"
            assertTrue(
                "Expected URL for ${book.name} to start with $expectedHost, got: ${client.urls.firstOrNull()}",
                client.urls.firstOrNull()?.startsWith(expectedHost) == true
            )
            // Only canonical BibleHub-covered books are expected to parse words.
            if (book.testament in listOf("Old", "New") && !book.isApocrypha) {
                assertTrue(
                    "Expected canonical book ${book.name} to parse at least one word, got $wordCount (thrown=$thrown)",
                    wordCount >= 1
                )
            }
        }
    }

    @Test
    fun numberedBooksUseUnderscoredSlug() {
        val fixture = loadFixture("biblehub/1_corinthians_1.html")
        val client = FixtureClient(fixture)
        val scraper = BibleScraper(client = client)

        val numberedBooks = listOf(
            "1Corinthians" to "1_corinthians",
            "2Corinthians" to "2_corinthians",
            "1Samuel" to "1_samuel",
            "2Samuel" to "2_samuel",
            "1Kings" to "1_kings",
            "2Kings" to "2_kings",
            "1Chronicles" to "1_chronicles",
            "2Chronicles" to "2_chronicles",
            "1Thessalonians" to "1_thessalonians",
            "2Thessalonians" to "2_thessalonians",
            "1Timothy" to "1_timothy",
            "2Timothy" to "2_timothy",
            "1Peter" to "1_peter",
            "2Peter" to "2_peter",
            "1John" to "1_john",
            "2John" to "2_john",
            "3John" to "3_john",
        )

        numberedBooks.forEach { (book, expectedSlug) ->
            client.urls.clear()
            runBlocking { scraper.scrapeInterlinear(book, 1) { _, _, _, _, _ -> } }
            assertEquals(
                "URL slug for $book",
                "https://biblehub.com/interlinear/$expectedSlug/1.htm",
                client.urls.first()
            )
        }
    }

    @Test
    fun unnumberedBooksUsePlainSlug() {
        val fixture = loadFixture("biblehub/1_corinthians_1.html")
        val client = FixtureClient(fixture)
        val scraper = BibleScraper(client = client)

        val unnumberedBooks = listOf(
            "Matthew" to "matthew",
            "Mark" to "mark",
            "Luke" to "luke",
            "John" to "john",
            "Acts" to "acts",
            "Romans" to "romans",
            "Galatians" to "galatians",
            "Ephesians" to "ephesians",
            "Philippians" to "philippians",
            "Colossians" to "colossians",
            "Titus" to "titus",
            "Philemon" to "philemon",
            "Hebrews" to "hebrews",
            "James" to "james",
            "Jude" to "jude",
            "Revelation" to "revelation",
            "Genesis" to "genesis",
            "Psalms" to "psalms",
        )

        unnumberedBooks.forEach { (book, expectedSlug) ->
            client.urls.clear()
            runBlocking { scraper.scrapeInterlinear(book, 1) { _, _, _, _, _ -> } }
            assertEquals(
                "URL slug for $book",
                "https://biblehub.com/interlinear/$expectedSlug/1.htm",
                client.urls.first()
            )
        }
    }

    @Test
    fun songOfSolomonMapsToSongs() {
        val fixture = loadFixture("biblehub/1_corinthians_1.html")
        val client = FixtureClient(fixture)
        val scraper = BibleScraper(client = client)
        client.urls.clear()
        runBlocking { scraper.scrapeInterlinear("Song of Solomon", 1) { _, _, _, _, _ -> } }
        assertEquals(
            "https://biblehub.com/interlinear/songs/1.htm",
            client.urls.first()
        )
    }

    @Test
    fun scrapeInterlinearSurfacesHttpError() {
        val scraper = BibleScraper(client = NotFoundClient())
        var thrown: Throwable? = null
        runBlocking {
            try {
                scraper.scrapeInterlinear("1Corinthians", 1) { _, _, _, _, _ -> }
            } catch (e: Throwable) {
                thrown = e
            }
        }
        assertTrue("Expected 404 to propagate as IOException", thrown is IOException)
    }
}
