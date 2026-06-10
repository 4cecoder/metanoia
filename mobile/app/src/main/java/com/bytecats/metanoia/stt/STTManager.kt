package com.bytecats.metanoia.stt

import android.content.Context
import android.util.Log
import com.bytecats.metanoia.gateway.GatewayClient
import com.bytecats.metanoia.settings.SettingsManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * STT manager — transcribes audio through the gateway Whisper endpoint.
 * Used for:
 *  - Voice search (speak a verse reference)
 *  - Audio note transcription
 *  - TTS quality verification (transcribe generated audio back to text)
 */
class STTManager(context: Context) {

    private val settings = SettingsManager(context)
    private val gateway = GatewayClient { settings.gatewayUrl }
    private val tag = "STTManager"

    /**
     * Transcribe audio bytes. Returns the text or null on failure.
     */
    suspend fun transcribe(audio: ByteArray, language: String = "en",
                           task: String = "transcribe"): String? =
        withContext(Dispatchers.IO) {
            try {
                val result = gateway.sttTranscribe(audio, "audio.wav", language, task)
                result?.optString("text")?.trim()
            } catch (e: Exception) {
                Log.e(tag, "Transcription failed: ${e.message}")
                null
            }
        }

    /**
     * Convenience overload: transcribe from a File.
     */
    suspend fun transcribe(file: java.io.File, language: String = "en",
                           task: String = "transcribe"): String? =
        transcribe(file.readBytes(), language, task)

    /**
     * Verify TTS output by transcribing it back.
     * Returns (transcribed_text, similarity_ok).
     */
    suspend fun verifyTts(generatedAudio: ByteArray, expectedText: String): Pair<String, Boolean>? =
        withContext(Dispatchers.IO) {
            try {
                val result = gateway.sttTranscribe(generatedAudio, "tts_check.wav")
                val transcribed = result?.optString("text")?.trim() ?: return@withContext null
                val ok = transcribed.lowercase().contains(expectedText.lowercase().take(20))
                Pair(transcribed, ok)
            } catch (e: Exception) {
                Log.e(tag, "TTS verification failed: ${e.message}")
                null
            }
        }

    /**
     * Translate audio (for non-English content).
     */
    suspend fun translate(audio: ByteArray, language: String = "auto"): String? =
        withContext(Dispatchers.IO) {
            try {
                val result = gateway.sttTranscribe(audio, "audio.wav", language, "translate")
                result?.optString("text")?.trim()
            } catch (e: Exception) { null }
        }
}
