package com.bytecats.metanoia.tts

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaPlayer
import android.util.Log
import com.bytecats.metanoia.gateway.GatewayClient
import com.bytecats.metanoia.settings.SettingsManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

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
    private val tag = "TTSManager"

    private var mediaPlayer: MediaPlayer? = null
    private var audioTrack: AudioTrack? = null

    // Android system TTS fallback
    private var systemTts: android.speech.tts.TextToSpeech? = null
    init {
        systemTts = android.speech.tts.TextToSpeech(context) { status ->
            if (status == android.speech.tts.TextToSpeech.SUCCESS) {
                systemTts?.language = java.util.Locale.US
            }
        }
    }

    // ------------------------------------------------------------------
    // Voice discovery & management
    // ------------------------------------------------------------------

    /**
     * Try to auto-discover the gateway on the local network.
     * Returns the URL if found, null otherwise.
     */
    suspend fun discoverServer(): String? = withContext(Dispatchers.IO) {
        // Check the currently configured URL first
        val current = settings.gatewayUrl
        if (gateway.health()) {
            logger("Gateway found at $current")
            return@withContext current
        }
        // Try common local network addresses
        val candidates = listOf(
            "http://192.168.122.2:8000",
            "http://192.168.1.100:8000",
            "http://10.0.2.2:8000", // Android emulator → host
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

    /**
     * Fetch the full list of registered voice profiles from the gateway.
     */
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

    /**
     * Delete a voice profile from the gateway.
     */
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

    /**
     * Create or update a voice profile (placeholder — audio uploaded separately).
     */
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

    /**
     * Upload reference audio for a voice profile.
     */
    suspend fun uploadSample(key: String, file: File): Boolean = withContext(Dispatchers.IO) {
        try {
            val res = gateway.uploadFile(
                "/tts/clone/voices/$key/audio",
                file,
                "audio/wav"
            )
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

    /**
     * Generate speech from text using a registered voice profile.
     * Returns a temp File containing WAV audio, or null on failure.
     */
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

    /**
     * Clone from arbitrary reference audio (no registered profile needed).
     */
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
    // Audio playback
    // ------------------------------------------------------------------

    /**
     * Play a WAV file via MediaPlayer (handles long audio well).
     */
    fun playAudio(file: File) {
        stop()
        try {
            mediaPlayer = MediaPlayer().apply {
                setDataSource(file.absolutePath)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                prepare()
                start()
            }
            logger("Playing ${file.name}")
        } catch (e: Exception) {
            Log.e(tag, "playAudio failed: ${e.message}")
            // Try AudioTrack fallback for raw WAV
            playPcmAudio(file.readBytes())
        }
    }

    fun stop() {
        mediaPlayer?.let { it.stop(); it.release() }
        mediaPlayer = null
        audioTrack?.let { it.stop(); it.release() }
        audioTrack = null
    }

    fun shutdown() {
        stop()
        systemTts?.shutdown()
    }

    fun isGatewayAvailable(): Boolean = gateway.health()

    // ------------------------------------------------------------------
    // Internal: raw PCM playback via AudioTrack
    // ------------------------------------------------------------------

    private fun playPcmAudio(wavBytes: ByteArray) {
        if (wavBytes.size < 44) return
        try {
            val sampleRate = ByteBuffer.wrap(wavBytes, 24, 4).order(ByteOrder.LITTLE_ENDIAN).int
            val channels = ByteBuffer.wrap(wavBytes, 22, 2).order(ByteOrder.LITTLE_ENDIAN).short.toInt()
            val bitsPerSample = ByteBuffer.wrap(wavBytes, 34, 2).order(ByteOrder.LITTLE_ENDIAN).short.toInt()

            var dataOffset = 44
            for (i in 36 until wavBytes.size - 4) {
                if (wavBytes[i] == 'd'.code.toByte() && wavBytes[i + 1] == 'a'.code.toByte() &&
                    wavBytes[i + 2] == 't'.code.toByte() && wavBytes[i + 3] == 'a'.code.toByte()) {
                    dataOffset = i + 8
                    break
                }
            }

            val pcmData = wavBytes.copyOfRange(dataOffset, wavBytes.size)
            val channelConfig = if (channels == 2) AudioFormat.CHANNEL_OUT_STEREO else AudioFormat.CHANNEL_OUT_MONO
            val encoding = if (bitsPerSample == 16) AudioFormat.ENCODING_PCM_16BIT else AudioFormat.ENCODING_PCM_8BIT

            val minBuf = AudioTrack.getMinBufferSize(sampleRate, channelConfig, encoding)
            val bufSize = maxOf(minBuf, pcmData.size)

            audioTrack = AudioTrack(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setChannelMask(channelConfig)
                    .setEncoding(encoding)
                    .build(),
                bufSize,
                AudioTrack.MODE_STATIC,
                AudioManager.AUDIO_SESSION_ID_GENERATE
            )

            audioTrack?.let { track ->
                track.write(pcmData, 0, pcmData.size)
                track.play()
            }
        } catch (e: Exception) {
            Log.e(tag, "AudioTrack playback failed: ${e.message}")
        }
    }
}
