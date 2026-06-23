package com.bytecats.metanoia.tts

import android.content.Context
import android.speech.tts.TextToSpeech
import android.util.Log
import com.bytecats.metanoia.gateway.GatewayClient
import com.bytecats.metanoia.models.RemoteVoice
import com.bytecats.metanoia.settings.SettingsManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

/**
 * TTS Manager — routes all synthesis through the AI VM Gateway.
 *
 * Gateway endpoints used:
 *  - GET  /tts/clone/voices/list      → list registered voice profiles
 *  - POST /tts/clone/voices/upsert     → create/update a voice profile
 *  - POST /tts/clone/voices/{key}/audio → upload reference audio
 *  - DELETE /tts/clone/voices/{key}     → delete a voice profile
 *  - POST /tts/clone/generate           → generate speech from registered voice
 *  - POST /tts/clone/dynamic            → clone from arbitrary audio
 *  - GET  /health                       → health check
 */
class TTSManager(
    private val context: Context,
    private val logger: (String) -> Unit = {}
) {
    private val settings = SettingsManager(context)
    private val gateway = GatewayClient { settings.gatewayUrl }
    private val audioPlayer = TTSAudioPlayer()
    private val tag = "TTSManager"

    private var systemTts: TextToSpeech? = null

    init {
        systemTts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                systemTts?.language = Locale.US
            }
        }
    }

    // ------------------------------------------------------------------
    // Voice discovery & management
    // ------------------------------------------------------------------

    suspend fun discoverServer(): String? = withContext(Dispatchers.IO) {
        val current = settings.gatewayUrl
        if (gateway.health()) {
            logger("Gateway found at $current")
            return@withContext current
        }
        val candidates = listOf(
            "http://192.168.122.2:8000",
            "http://192.168.1.100:8000",
            "http://10.0.2.2:8000",
            "http://localhost:8000"
        )
        for (url in candidates) {
            val test = GatewayClient { url }
            if (test.health()) {
                logger("Auto-discovered gateway at $url")
                settings.gatewayIp = url.substringAfter("http://").substringBefore(":")
                settings.gatewayPort = url.substringAfterLast(":")
                return@withContext url
            }
        }
        logger("No gateway found on local network")
        null
    }

    suspend fun fetchFullStatus(): List<RemoteVoice> = withContext(Dispatchers.IO) {
        if (!gateway.health()) return@withContext emptyList()
        try {
            val json = gateway.getJson("/tts/clone/voices/list") ?: return@withContext emptyList()
            val arr = json.optJSONArray("voices") ?: json.optJSONArray("data") ?: return@withContext emptyList()
            val voices = mutableListOf<RemoteVoice>()
            for (i in 0 until arr.length()) {
                val v = arr.optJSONObject(i) ?: continue
                voices.add(RemoteVoice(
                    key = v.optString("key", v.optString("name", v.optString("id", ""))),
                    displayName = v.optString("display_name", v.optString("name", v.optString("key", "Unknown"))),
                    exists = v.optBoolean("has_audio", v.optBoolean("exists", false)),
                    type = v.optString("type", "cloned")
                ))
            }
            voices
        } catch (e: Exception) {
            Log.e(tag, "fetchFullStatus failed: ${e.message}")
            emptyList()
        }
    }

    suspend fun deleteVoice(key: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val res = gateway.delete("/tts/clone/voices/$key")
            logger("Voice delete '$key': ${if (res) "OK" else "FAIL"}")
            res
        } catch (e: Exception) {
            Log.e(tag, "deleteVoice failed: ${e.message}")
            false
        }
    }

    suspend fun upsertVoice(name: String, refText: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val body = JSONObject().apply {
                put("key", name)
                put("display_name", name)
                put("ref_text", refText)
            }.toString()
            val res = gateway.postJson("/tts/clone/voices/upsert", body) != null
            logger("Voice upsert '$name': ${if (res) "OK" else "FAIL"}")
            res
        } catch (e: Exception) {
            Log.e(tag, "upsertVoice failed: ${e.message}")
            false
        }
    }

    suspend fun uploadSample(key: String, file: File): Boolean = withContext(Dispatchers.IO) {
        try {
            val res = gateway.uploadFile("/tts/clone/voices/$key/audio", file, "audio/wav")
            logger("Upload audio for '$key': ${if (res) "OK" else "FAIL"}")
            res
        } catch (e: Exception) {
            Log.e(tag, "uploadSample failed: ${e.message}")
            false
        }
    }

    // ------------------------------------------------------------------
    // Speech generation
    // ------------------------------------------------------------------

    suspend fun generateSpeech(text: String, voiceKey: String): File? = withContext(Dispatchers.IO) {
        if (text.isBlank()) return@withContext null
        try {
            val audio = gateway.ttsClone(text, voiceKey)
            if (audio != null && audio.size > 44) {
                val outFile = File(context.cacheDir, "tts_${System.currentTimeMillis()}.wav")
                FileOutputStream(outFile).use { it.write(audio) }
                logger("Generated ${audio.size}B for voice '$voiceKey'")
                outFile
            } else {
                logger("Gateway returned empty audio for '$voiceKey'")
                null
            }
        } catch (e: Exception) {
            Log.e(tag, "generateSpeech failed: ${e.message}")
            logger("TTS error: ${e.message}")
            null
        }
    }

    suspend fun cloneDynamic(text: String, refAudio: ByteArray, refText: String = ""): File? =
        withContext(Dispatchers.IO) {
            try {
                val audio = gateway.ttsCloneDynamic(text, refAudio, refText)
                if (audio != null && audio.size > 44) {
                    val outFile = File(context.cacheDir, "tts_dyn_${System.currentTimeMillis()}.wav")
                    FileOutputStream(outFile).use { it.write(audio) }
                    outFile
                } else null
            } catch (e: Exception) {
                Log.e(tag, "cloneDynamic failed: ${e.message}")
                null
            }
        }

    // ------------------------------------------------------------------
    // Audio playback (delegated to TTSAudioPlayer)
    // ------------------------------------------------------------------

    fun playAudio(file: File) = audioPlayer.play(file)
    fun stop() { audioPlayer.stop() }

    fun shutdown() {
        stop()
        systemTts?.shutdown()
    }

    fun isGatewayAvailable(): Boolean = gateway.health()
}
