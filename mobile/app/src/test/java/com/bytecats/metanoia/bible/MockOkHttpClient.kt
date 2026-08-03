package com.bytecats.metanoia.bible

import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okio.Buffer
import okio.Timeout
import java.io.IOException

/**
 * Mock OkHttpClient that returns cached HTML instead of making network requests.
 *
 * Used in unit tests to test scraper parsing logic without hitting real endpoints.
 */
class MockOkHttpClient(private val cachedResponses: Map<String, String>) : Call.Factory {

    override fun newCall(request: Request): Call {
        val cachedHtml = cachedResponses[request.url.toString()]
            ?: cachedResponses.keys.firstOrNull { request.url.toString().contains(it) }?.let { cachedResponses[it] }
            ?: throw IOException("No cached response for URL: ${request.url}")

        return MockCall(request, cachedHtml)
    }

    private class MockCall(
        private val request: Request,
        private val cachedHtml: String
    ) : Call {
        private var executed = false
        private var cancelled = false

        override fun execute(): Response {
            if (executed) throw IllegalStateException("Already Executed")
            if (cancelled) throw IOException("Canceled")
            executed = true

            return Response.Builder()
                .request(request)
                .code(200)
                .message("OK")
                .protocol(Protocol.HTTP_1_1)
                .body(ResponseBody.create("text/html".toMediaType(), cachedHtml))
                .build()
        }

        override fun enqueue(responseCallback: Callback) {
            throw UnsupportedOperationException("Synchronous only")
        }

        override fun cancel() {
            cancelled = true
        }

        override fun isExecuted(): Boolean = executed

        override fun isCanceled(): Boolean = cancelled

        override fun clone(): Call {
            return MockCall(request, cachedHtml)
        }

        override fun request(): Request = request

        override fun timeout(): Timeout = Timeout()
    }
}