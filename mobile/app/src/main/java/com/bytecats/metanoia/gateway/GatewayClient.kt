package com.bytecats.metanoia.gateway

import android.util.Log
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Unified HTTP client for the AI VM Gateway.
 * All managers (TTS, STT, Bible) route through this.
 */
class GatewayClient(private val baseUrlProvider: () -> String) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)   // TTS generation can be slow
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val tag = "GatewayClient"

    private val baseUrl: String get() = baseUrlProvider().trimEnd('/')

    // -----------------------------------------------------------------------
    // Health & connectivity
    // -----------------------------------------------------------------------

    fun health(): Boolean {
        return try {
            val req = Request.Builder().url("$baseUrl/health").get().build()
            client.newCall(req).execute().use { it.isSuccessful }
        } catch (e: Exception) {
            Log.w(tag, "Health check failed: ${e.message}")
            false
        }
    }

    fun ttsCloneHealth(): JSONObject? {
        return try {
            val req = Request.Builder().url("$baseUrl/tts/clone/health").get().build()
            client.newCall(req).execute().use { resp ->
                if (resp.isSuccessful) JSONObject(resp.body?.string() ?: "{}")
                else null
            }
        } catch (e: Exception) { null }
    }

    // -----------------------------------------------------------------------
    // Bible API — all prefixed /bible
    // -----------------------------------------------------------------------

    fun bibleBooks(): JSONObject? = getJson("/bible/books")

    fun bibleChapter(book: String, chapter: Int, version: String = "NKJV"): JSONObject? =
        getJson("/bible/$book/$chapter?version=$version")

    fun bibleVerse(book: String, chapter: Int, verse: Int): JSONObject? =
        getJson("/bible/$book/$chapter/$verse")

    fun bibleSearch(query: String, limit: Int = 50): JSONObject? =
        getJson("/bible/search/text?q=${java.net.URLEncoder.encode(query, "UTF-8")}&limit=$limit")

    fun bibleInterlinear(book: String, chapter: Int, verse: Int? = null): JSONObject? {
        val url = if (verse != null) "/bible/$book/$chapter/interlinear?verse=$verse"
                  else "/bible/$book/$chapter/interlinear"
        return getJson(url)
    }

    fun bibleLexicon(strongs: String): JSONObject? = getJson("/bible/lexicon/$strongs")

    fun bibleCrossRefs(book: String, chapter: Int, verse: Int): JSONObject? =
        getJson("/bible/$book/$chapter/$verse/xref")

    fun bibleChapterSummary(book: String, chapter: Int): JSONObject? =
        getJson("/bible/$book/$chapter/summary")

    fun bibleHighlights(book: String, chapter: Int): JSONObject? =
        getJson("/bible/$book/$chapter/highlights")

    fun bibleBookMetadata(book: String): JSONObject? = getJson("/bible/$book/metadata")

    // Bible write operations
    fun bibleSetHighlight(book: String, chapter: Int, verse: Int, color: String): JSONObject? =
        putJson("/bible/$book/$chapter/$verse/highlight", """{"color":"$color"}""")

    fun bibleDeleteHighlight(book: String, chapter: Int, verse: Int): Boolean =
        delete("/bible/$book/$chapter/$verse/highlight")

    fun bibleSaveNote(book: String, chapter: Int, verse: Int, content: String): JSONObject? =
        putJson("/bible/$book/$chapter/$verse/note", JSONObject().put("content", content).toString())

    fun bibleDeleteNote(book: String, chapter: Int, verse: Int): Boolean =
        delete("/bible/$book/$chapter/$verse/note")

    fun bibleListNotes(book: String? = null): JSONObject? {
        val url = if (book != null) "/bible/notes?book=$book" else "/bible/notes"
        return getJson(url)
    }

    fun bibleAddLexiconFavorite(strongs: String, lemma: String = "", definition: String = ""): JSONObject? =
        postJson("/bible/lexicon/$strongs/favorite", JSONObject()
            .put("lemma", lemma).put("definition", definition).toString())

    fun bibleStats(): JSONObject? = getJson("/bible/stats")

    fun bibleCacheBook(book: String): JSONObject? = postJson("/bible/cache/$book", "{}")

    // -----------------------------------------------------------------------
    // TTS — Kokoro (lightweight, fast)
    // -----------------------------------------------------------------------

    fun ttsKokoro(text: String, voice: String = "af_nicole"): ByteArray? {
        val url = "$baseUrl/tts/kokoro?text=${java.net.URLEncoder.encode(text, "UTF-8")}" +
                  "&voice=${java.net.URLEncoder.encode(voice, "UTF-8")}"
        return getBytes(url)
    }

    // -----------------------------------------------------------------------
    // TTS — Voice Clone (Qwen3-TTS zero-shot)
    // -----------------------------------------------------------------------

    fun ttsClone(text: String, voice: String = "default"): ByteArray? {
        val url = "$baseUrl/tts/clone?text=${java.net.URLEncoder.encode(text, "UTF-8")}" +
                  "&voice=${java.net.URLEncoder.encode(voice, "UTF-8")}"
        return getBytes(url)
    }

    fun ttsCloneDynamic(text: String, refAudio: ByteArray, refText: String = ""): ByteArray? {
        val multipart = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("text", text)
            .addFormDataPart("file", "ref.wav",
                refAudio.toRequestBody("audio/wav".toMediaTypeOrNull()))
            .apply { if (refText.isNotEmpty()) addFormDataPart("ref_text", refText) }
            .build()
        val req = Request.Builder().url("$baseUrl/tts/clone/dynamic").post(multipart).build()
        return client.newCall(req).execute().use { resp ->
            if (resp.isSuccessful) resp.body?.bytes() else null
        }
    }

    // -----------------------------------------------------------------------
    // TTS — Voice DB (profile management)
    // -----------------------------------------------------------------------

    fun voiceList(tag: String? = null): JSONObject? {
        val url = if (tag != null) "/tts/clone/voices?tag=$tag" else "/tts/clone/voices"
        return getJson(url)
    }

    fun voiceSearch(query: String): JSONObject? =
        getJson("/tts/clone/voices/search?q=${java.net.URLEncoder.encode(query, "UTF-8")}")

    fun voiceGet(name: String): JSONObject? = getJson("/tts/clone/voices/$name")

    fun voiceGenerate(name: String, text: String): ByteArray? {
        val multipart = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("text", text).build()
        val req = Request.Builder().url("$baseUrl/tts/clone/voices/$name/generate").post(multipart).build()
        return client.newCall(req).execute().use { resp ->
            if (resp.isSuccessful) resp.body?.bytes() else null
        }
    }

    fun voiceUpload(name: String, audio: ByteArray, transcript: String = "",
                    tags: String = "", description: String = ""): JSONObject? {
        val multipart = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("name", name)
            .addFormDataPart("audio", "upload.wav",
                audio.toRequestBody("audio/wav".toMediaTypeOrNull()))
            .apply {
                if (transcript.isNotEmpty()) addFormDataPart("transcript", transcript)
                if (tags.isNotEmpty()) addFormDataPart("tags", tags)
                if (description.isNotEmpty()) addFormDataPart("description", description)
            }.build()
        val req = Request.Builder().url("$baseUrl/tts/clone/voices/upload").post(multipart).build()
        return client.newCall(req).execute().use { resp ->
            if (resp.isSuccessful) JSONObject(resp.body?.string() ?: "{}") else null
        }
    }

    fun voiceDelete(name: String): Boolean = delete("/tts/clone/voices/$name")

    // -----------------------------------------------------------------------
    // Bible Audio (TTS-narrated chapters)
    // -----------------------------------------------------------------------

    fun bibleChapterAudio(book: String, chapter: Int, voice: String = "af_nicole"): ByteArray? {
        val multipart = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("voice", voice).build()
        val req = Request.Builder().url("$baseUrl/bible/$book/$chapter/audio").post(multipart).build()
        return client.newCall(req).execute().use { resp ->
            if (resp.isSuccessful) resp.body?.bytes() else null
        }
    }

    // -----------------------------------------------------------------------
    // STT — Transcription (Whisper)
    // -----------------------------------------------------------------------

    fun sttTranscribe(audio: ByteArray, filename: String = "audio.wav",
                      language: String = "en", task: String = "transcribe"): JSONObject? {
        val multipart = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("file", filename,
                audio.toRequestBody("audio/wav".toMediaTypeOrNull()))
            .addFormDataPart("language", language)
            .addFormDataPart("task", task)
            .build()
        val req = Request.Builder().url("$baseUrl/stt/transcribe").post(multipart).build()
        return client.newCall(req).execute().use { resp ->
            val body = resp.body?.string() ?: "{}"
            if (resp.isSuccessful) JSONObject(body) else null
        }
    }

    // -----------------------------------------------------------------------
    // Public raw helpers (for managers that need direct path access)
    // -----------------------------------------------------------------------

    fun getJson(path: String): JSONObject? = doGetJson(path)

    fun postJson(path: String, jsonBody: String): JSONObject? = doPostJson(path, jsonBody)

    fun putJson(path: String, jsonBody: String): JSONObject? = doPutJson(path, jsonBody)

    fun delete(path: String): Boolean = doDelete(path)

    fun uploadFile(path: String, file: File, contentType: String): Boolean {
        return try {
            val multipart = MultipartBody.Builder().setType(MultipartBody.FORM)
                .addFormDataPart("file", file.name,
                    file.readBytes().toRequestBody(contentType.toMediaTypeOrNull()))
                .build()
            val req = Request.Builder().url("$baseUrl$path").post(multipart).build()
            client.newCall(req).execute().use { it.isSuccessful }
        } catch (e: Exception) {
            Log.w(tag, "Upload to $path failed: ${e.message}")
            false
        }
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    private fun doGetJson(path: String): JSONObject? {
        return try {
            val req = Request.Builder().url("$baseUrl$path").get().build()
            client.newCall(req).execute().use { resp ->
                if (resp.isSuccessful) JSONObject(resp.body?.string() ?: "{}") else null
            }
        } catch (e: Exception) {
            Log.w(tag, "GET $path failed: ${e.message}")
            null
        }
    }

    private fun doPostJson(path: String, jsonBody: String): JSONObject? {
        return try {
            val body = jsonBody.toRequestBody("application/json".toMediaType())
            val req = Request.Builder().url("$baseUrl$path").post(body).build()
            client.newCall(req).execute().use { resp ->
                if (resp.isSuccessful) JSONObject(resp.body?.string() ?: "{}") else null
            }
        } catch (e: Exception) { null }
    }

    private fun doPutJson(path: String, jsonBody: String): JSONObject? {
        return try {
            val body = jsonBody.toRequestBody("application/json".toMediaType())
            val req = Request.Builder().url("$baseUrl$path").put(body).build()
            client.newCall(req).execute().use { resp ->
                if (resp.isSuccessful) JSONObject(resp.body?.string() ?: "{}") else null
            }
        } catch (e: Exception) { null }
    }

    private fun doDelete(path: String): Boolean {
        return try {
            val req = Request.Builder().url("$baseUrl$path").delete().build()
            client.newCall(req).execute().use { it.isSuccessful }
        } catch (e: Exception) { false }
    }

    private fun getBytes(url: String): ByteArray? {
        return try {
            val req = Request.Builder().url(url).get().build()
            client.newCall(req).execute().use { resp ->
                if (resp.isSuccessful) resp.body?.bytes() else null
            }
        } catch (e: Exception) {
            Log.w(tag, "GET bytes failed: ${e.message}")
            null
        }
    }
}
