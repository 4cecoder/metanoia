package com.bytecats.metanoia.tts

import android.content.Context
import android.media.AudioFormat
import android.media.AudioTrack
import android.net.Uri
import android.util.Log
import com.bytecats.metanoia.settings.SettingsManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

data class RemoteVoice(
    val key: String,
    val displayName: String,
    val exists: Boolean,
    val type: String,
    val text: String? = null
)

class TTSManager(private val context: Context, private val logger: (String) -> Unit) {
    private val TAG = "TTSManager"
    private val client = OkHttpClient.Builder()
        .connectTimeout(2, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()
    
    private val cacheDir: File = File(context.cacheDir, "tts_cache").apply { mkdirs() }
    private val settings = SettingsManager(context)

    fun clearCache() {
        cacheDir.listFiles()?.forEach { it.delete() }
        logger("Cache cleared.")
    }

    suspend fun discoverServer(): String? = withContext(Dispatchers.IO) {
        val subnets = listOf("192.168.1", "192.168.0", "10.0.0")
        logger("Auto-discovery initiated...")
        
        for (subnet in subnets) {
            for (i in 1..254) {
                val url = "http://$subnet.$i:8000/system_info"
                if (probe(url)) {
                    val serverUrl = "http://$subnet.$i:8000"
                    logger("Success: Found Metanoia at $serverUrl")
                    return@withContext serverUrl
                }
            }
        }
        logger("Discovery timed out. Manual entry required.")
        null
    }

    private fun probe(url: String): Boolean {
        return try {
            val request = Request.Builder().url(url).build()
            client.newCall(request).execute().use { it.isSuccessful }
        } catch (e: Exception) { false }
    }

    suspend fun fetchFullStatus(): List<RemoteVoice> = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder().url("${settings.ttsServerUrl}/voice_status").build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext emptyList()
                val json = JSONObject(response.body?.string() ?: "{}")
                val list = mutableListOf<RemoteVoice>()
                json.keys().forEach { key ->
                    val obj = json.getJSONObject(key)
                    list.add(RemoteVoice(
                        key = key,
                        displayName = obj.optString("display_name", key),
                        exists = obj.optBoolean("exists", false),
                        type = obj.optString("type", "cloned"),
                        text = obj.optString("text", "")
                    ))
                }
                list
            }
        } catch (e: Exception) { emptyList() }
    }

    suspend fun upsertVoice(name: String, text: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val json = JSONObject().apply {
                put("name", name)
                put("text", text)
                put("mode", "speedy")
            }
            val request = Request.Builder()
                .url("${settings.ttsServerUrl}/voices")
                .post(json.toString().toRequestBody("application/json".toMediaType()))
                .build()
            client.newCall(request).execute().use { it.isSuccessful }
        } catch (e: Exception) { false }
    }

    suspend fun deleteVoice(key: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder()
                .url("${settings.ttsServerUrl}/voices/$key")
                .delete()
                .build()
            client.newCall(request).execute().use { it.isSuccessful }
        } catch (e: Exception) { false }
    }

    suspend fun uploadSample(voiceKey: String, file: File): Boolean = withContext(Dispatchers.IO) {
        try {
            val body = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("voice", voiceKey)
                .addFormDataPart("file", file.name, file.asRequestBody("audio/wav".toMediaType()))
                .build()
            val request = Request.Builder()
                .url("${settings.ttsServerUrl}/upload_voice_sample")
                .post(body)
                .build()
            client.newCall(request).execute().use { it.isSuccessful }
        } catch (e: Exception) { false }
    }

    suspend fun generateSpeech(text: String, voice: String): File? = withContext(Dispatchers.IO) {
        val cacheKey = md5("$text|$voice|${settings.ttsServerUrl}")
        val cacheFile = File(cacheDir, "tts_$cacheKey.wav")
        if (cacheFile.exists() && cacheFile.length() > 44) return@withContext cacheFile

        try {
            val json = JSONObject().apply {
                put("text", text); put("voice", voice.lowercase()); put("speed", 1.0); put("mode", "speedy")
            }
            val request = Request.Builder()
                .url("${settings.ttsServerUrl}/generate")
                .post(json.toString().toRequestBody("application/json".toMediaType()))
                .build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext null
                val body = response.body ?: return@withContext null
                FileOutputStream(cacheFile).use { out -> body.byteStream().use { it.copyTo(out) } }
                cacheFile
            }
        } catch (e: Exception) { null }
    }

    private fun md5(input: String): String {
        return MessageDigest.getInstance("MD5").digest(input.toByteArray()).joinToString("") { "%02x".format(it) }
    }

    suspend fun playAudio(file: File) = withContext(Dispatchers.IO) {
        try {
            val bytes = file.readBytes()
            if (bytes.size < 44) return@withContext
            val pcmData = bytes.sliceArray(44 until bytes.size)
            val track = AudioTrack.Builder()
                .setAudioAttributes(android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setAudioFormat(AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(24000)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setBufferSizeInBytes(pcmData.size).setTransferMode(AudioTrack.MODE_STATIC).build()
            track.write(pcmData, 0, pcmData.size); track.play()
            delay((pcmData.size.toFloat() / 2 / 24000 * 1000).toLong() + 100)
            track.stop(); track.release()
        } catch (e: Exception) { Log.e(TAG, "Playback fail: ${e.message}") }
    }
}
