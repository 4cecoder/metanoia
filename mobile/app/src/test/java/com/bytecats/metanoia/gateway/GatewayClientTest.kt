package com.bytecats.metanoia.gateway

import com.bytecats.metanoia.gateway.GatewayClient
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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

/**
 * Behavioral coverage for GatewayClient, using the same hand-written fake
 * okhttp3.Call.Factory trick as BibleScraperTest — GatewayClient now takes
 * an injectable Call.Factory (defaulting to a real OkHttpClient) so this
 * doesn't need real network access.
 *
 * @deprecated GatewayClient is deprecated. Tests maintained for backward compatibility.
 */
@Deprecated("GatewayClient tests are deprecated but maintained for compatibility.", level = DeprecationLevel.WARNING)
class GatewayClientTest {

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

    private class FixedResponseCall(
        private val req: Request,
        private val code: Int,
        private val bodyJson: String?
    ) : Call {
        override fun request(): Request = req
        override fun execute(): Response {
            // OkHttp's Response requires a non-null body even for an "empty"
            // response, so always attach one (empty string when the test
            // doesn't care about the body content).
            val builder = Response.Builder()
                .request(req)
                .protocol(Protocol.HTTP_1_1)
                .code(code)
                .message(if (code in 200..299) "OK" else "Error")
                .body((bodyJson ?: "").toResponseBody("application/json".toMediaType()))
            return builder.build()
        }
        override fun enqueue(responseCallback: Callback) = responseCallback.onResponse(this, execute())
        override fun cancel() {}
        override fun isExecuted(): Boolean = false
        override fun isCanceled(): Boolean = false
        override fun timeout(): Timeout = Timeout.NONE
        override fun clone(): Call = this
    }

    private fun failingClient() = Call.Factory { request -> FailingCall(request) }
    private fun fixedClient(code: Int, bodyJson: String?) =
        Call.Factory { request -> FixedResponseCall(request, code, bodyJson) }

    // -------------------------------------------------------------------
    // health()
    // -------------------------------------------------------------------

    @Test
    fun healthTrueOnSuccessfulResponse() {
        val gateway = GatewayClient(client = fixedClient(200, null), baseUrlProvider = { "http://example.invalid" })
        assertTrue(gateway.health())
    }

    @Test
    fun healthFalseOnErrorResponseCode() {
        val gateway = GatewayClient(client = fixedClient(500, null), baseUrlProvider = { "http://example.invalid" })
        assertFalse(gateway.health())
    }

    @Test
    fun healthFalseWhenCallThrows() {
        val gateway = GatewayClient(client = failingClient(), baseUrlProvider = { "http://example.invalid" })
        assertFalse(gateway.health())
    }

    // -------------------------------------------------------------------
    // getJson()
    // -------------------------------------------------------------------

    @Test
    fun getJsonReturnsParsedObjectOn200() {
        val gateway = GatewayClient(client = fixedClient(200, """{"status":"ok","count":3}"""), baseUrlProvider = { "http://example.invalid" })
        val result = gateway.getJson("/bible/books")
        assertEquals("ok", result?.optString("status"))
        assertEquals(3, result?.optInt("count"))
    }

    @Test
    fun getJsonReturnsNullOnNonSuccessfulResponse() {
        val gateway = GatewayClient(client = fixedClient(404, """{"error":"not found"}"""), baseUrlProvider = { "http://example.invalid" })
        assertNull(gateway.getJson("/bible/books"))
    }

    @Test
    fun getJsonReturnsNullInsteadOfThrowingOnNetworkFailure() {
        val gateway = GatewayClient(client = failingClient(), baseUrlProvider = { "http://example.invalid" })
        assertNull(gateway.getJson("/bible/books"))
    }
}
