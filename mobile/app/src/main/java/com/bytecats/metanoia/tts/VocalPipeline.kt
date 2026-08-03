package com.bytecats.metanoia.tts

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Vocal Pipeline — text-to-speech pipeline for Bible reading.
 *
 * Workflow:
 * 1. Receive text (from UI, search, or external source)
 * 2. Generate speech from text via AI VM Gateway (Qwen3-TTS voice cloning or Kokoro)
 * 3. Playback generated audio (via TTSManager which uses TTSAudioPlayer)
 *
 * Use cases:
 * - Read verse: "Genesis 1:1" → TTS reads the verse
 * - Read chapter: "Psalms 23" → TTS reads the chapter
 * - Bible Q&A: "What does Romans 8 say?" → TTS reads Romans 8
 * - Voice navigation: User selects text → TTS reads it
 *
 * No audio recording - text is provided by the UI or other sources.
 *
 * Engine options (via TTSManager):
 * - Voice Clone: Qwen3-TTS zero-shot voice cloning (high quality, uses registered voices)
 * - Dynamic Clone: Qwen3-TTS cloning from arbitrary audio reference
 * - Kokoro: Lightweight neural TTS (fast, good for long passages)
 *
 * Uses existing TTSManager for generation and TTSAudioPlayer for playback.
 */
class VocalPipeline(
    private val context: Context,
    private val ttsManager: TTSManager,
    private val onGeneration: ((java.io.File?) -> Unit)? = null,
    private val onError: ((String) -> Unit)? = null
) {
    private val tag = "VocalPipeline"

    /**
     * Generate speech from text using voice clone (Qwen3-TTS).
     *
     * Uses a pre-registered voice profile on the gateway.
     *
     * @param text Text to convert to speech
     * @param voiceKey Voice profile key (default, custom, etc.)
     * @return Generated audio file (null on failure)
     */
    suspend fun speakWithVoiceClone(
        text: String,
        voiceKey: String = "default"
    ): java.io.File? = withContext(Dispatchers.IO) {
        if (text.isBlank()) {
            val msg = "Cannot speak empty text"
            Log.e(tag, msg)
            onError?.invoke(msg)
            return@withContext null
        }

        if (!ttsManager.isGatewayAvailable()) {
            val msg = "AI VM Gateway not available"
            Log.e(tag, msg)
            onError?.invoke(msg)
            return@withContext null
        }

        try {
            Log.i(tag, "Generating speech (Qwen3-TTS clone) for \"$text\"...")
            val audioFile = ttsManager.generateSpeech(text, voiceKey)

            if (audioFile != null) {
                Log.i(tag, "Generated ${audioFile.length()}B for voice '$voiceKey'")
                onGeneration?.invoke(audioFile)
                
                // TTSManager handles playback via playAudio()
                // Note: generateSpeech() doesn't auto-play, so we need to call it explicitly
                // Or use TTSManager.playAudio(audioFile)
                
                return@withContext audioFile
            } else {
                val msg = "Voice clone generation returned null for '$voiceKey'"
                Log.e(tag, msg)
                onError?.invoke(msg)
                return@withContext null
            }
        } catch (e: Exception) {
            val msg = "Voice clone generation failed: ${e.message}"
            Log.e(tag, msg, e)
            onError?.invoke(msg)
            return@withContext null
        }
    }

    /**
     * Dynamic voice cloning - clone from arbitrary audio reference.
     *
     * @param text Text to speak
     * @param refAudio Reference audio bytes (the voice to clone)
     * @param refText Optional transcript of reference audio
     * @return Generated audio file (null on failure)
     */
    suspend fun speakWithDynamicClone(
        text: String,
        refAudio: ByteArray,
        refText: String = ""
    ): java.io.File? = withContext(Dispatchers.IO) {
        if (text.isBlank()) {
            onError?.invoke("Cannot speak empty text")
            return@withContext null
        }

        if (!ttsManager.isGatewayAvailable()) {
            onError?.invoke("AI VM Gateway not available")
            return@withContext null
        }

        try {
            Log.i(tag, "Generating speech (Qwen3-TTS dynamic clone)...")
            val audioFile = ttsManager.cloneDynamic(text, refAudio, refText)

            if (audioFile != null) {
                Log.i(tag, "Generated ${audioFile.length()}B with dynamic clone")
                onGeneration?.invoke(audioFile)
                return@withContext audioFile
            } else {
                onError?.invoke("Dynamic clone generation returned null")
                return@withContext null
            }
        } catch (e: Exception) {
            Log.e(tag, "Dynamic clone failed: ${e.message}")
            onError?.invoke(e.message ?: "Unknown error")
            return@withContext null
        }
    }

    /**
     * Generate and play speech using voice clone (one-shot convenience).
     *
     * @param text Text to speak
     * @param voiceKey Voice profile key
     * @return Generated audio file (null on failure)
     */
    suspend fun speak(
        text: String,
        voiceKey: String = "default"
    ): java.io.File? {
        val audioFile = speakWithVoiceClone(text, voiceKey)
        if (audioFile != null) {
            ttsManager.playAudio(audioFile)
        }
        return audioFile
    }

    /**
     * Speak multiple texts sequentially (verses, chapters, etc.).
     *
     * @param texts List of texts to speak
     * @param voiceKey Voice profile key to use
     * @param onProgress Callback with (index, total, currentText)
     */
    suspend fun speakSequence(
        texts: List<String>,
        voiceKey: String = "default",
        onProgress: ((Int, Int, String) -> Unit)? = null
    ) = withContext(Dispatchers.IO) {
        if (texts.isEmpty()) {
            onError?.invoke("No texts to speak")
            return@withContext
        }

        if (!ttsManager.isGatewayAvailable()) {
            onError?.invoke("AI VM Gateway not available")
            return@withContext
        }

        try {
            texts.forEachIndexed { index, text ->
                if (text.isBlank()) return@forEachIndexed

                onProgress?.invoke(index + 1, texts.size, text)

                val audioFile = speakWithVoiceClone(text, voiceKey)
                if (audioFile != null) {
                    ttsManager.playAudio(audioFile)
                    
                    // Wait for playback to complete
                    kotlinx.coroutines.delay(audioFile.length() / 16000L * 1000)
                }

                // Small pause between segments
                kotlinx.coroutines.delay(300)
            }
        } catch (e: Exception) {
            Log.e(tag, "Sequence playback failed: ${e.message}")
            onError?.invoke(e.message ?: "Unknown error")
        }
    }

    /**
     * Stop any ongoing playback.
     */
    fun stop() {
        ttsManager.stop()
    }

    /**
     * Check if pipeline is ready to use.
     */
    fun isReady(): Boolean {
        return ttsManager.isGatewayAvailable()
    }

    /**
     * Shutdown and cleanup.
     */
    fun shutdown() {
        stop()
    }
}