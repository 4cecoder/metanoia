package com.bytecats.metanoia.bible

import android.database.sqlite.SQLiteDatabase
import com.bytecats.metanoia.bible.lexicon.HebrewLexiconRepository
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.ArgumentCaptor
import org.mockito.Mockito.*

class HebrewLexiconRepositoryTest {
    
    @Test
    fun testValidHtmlResponse_extractsData() {
        val mockHtml = """
            <html>
                <body>
                    <span class="hebrew">בראשית</span>
                    <span class="translit">bereshith</span>
                    <div class="strongsnt">beginning, chief</div>
                </body>
            </html>
        """.trimIndent()
        
        val client = getMockClient(mockHtml, 200)
        val mockDb = mock(SQLiteDatabase::class.java)
        
        val repo = HebrewLexiconRepository(client) { mockDb }
        repo.scrapeHebrewStrong("7225")
        
        val sqlCaptor = ArgumentCaptor.forClass(String::class.java)
        val argsCaptor = ArgumentCaptor.forClass(Array<Any>::class.java)
        
        verify(mockDb, atLeastOnce()).execSQL(sqlCaptor.capture(), argsCaptor.capture())
        
        var foundMain = false
        var foundAlt = false
        for (args in argsCaptor.allValues) {
            val strongs = args[0] as String
            val lemma = args[1] as String
            val tr = args[2] as String
            val def = args[3] as String
            if (strongs == "H7225") {
                assertEquals("בראשית", lemma)
                assertEquals("bereshith", tr)
                assertEquals("beginning, chief", def)
                foundMain = true
            }
            if (strongs == "7225") {
                foundAlt = true
            }
        }
        assertTrue("Should have inserted H7225", foundMain)
        assertTrue("Should have inserted 7225", foundAlt)
    }

    @Test
    fun testFallback_whenNetworkFails() {
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            throw java.io.IOException("Network error")
        }.build()
        val mockDb = mock(SQLiteDatabase::class.java)
        
        val repo = HebrewLexiconRepository(client) { mockDb }
        repo.scrapeHebrewStrong("H1234")
        
        val sqlCaptor = ArgumentCaptor.forClass(String::class.java)
        val argsCaptor = ArgumentCaptor.forClass(Array<Any>::class.java)
        
        verify(mockDb, atLeastOnce()).execSQL(sqlCaptor.capture(), argsCaptor.capture())
        
        var foundFallback = false
        for (args in argsCaptor.allValues) {
            val strongs = args[0] as String
            val lemma = args[1] as String
            val def = args[3] as String
            if (strongs == "H1234") {
                assertEquals("N/A", lemma)
                assertTrue(def.contains("Definition unavailable"))
                foundFallback = true
            }
        }
        assertTrue(foundFallback)
    }
    
    private fun getMockClient(body: String, code: Int): OkHttpClient {
        return OkHttpClient.Builder().addInterceptor { chain ->
            Response.Builder()
                .code(code)
                .message("Mock")
                .request(chain.request())
                .protocol(Protocol.HTTP_1_1)
                .body(body.toResponseBody("text/html".toMediaTypeOrNull()))
                .build()
        }.build()
    }
}
