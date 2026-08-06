package com.bytecats.metanoia.tts

import android.content.Context
import android.util.Log
import com.bytecats.metanoia.settings.SettingsManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

/**
 * Native TTS Service - Complete replacement for gateway-based TTS.
 *
 * This service provides all TTS functionality using the native Qwen3-TTS forward pass,
 * eliminating dependencies on external gateway services.
 *
 * Features:
 * - Neural text-to-speech synthesis using Qwen3-TTS
 * - GGUF model loading and management
 * - Voice selection via GGUF model files
 * - Speed and pitch adjustment
 * - Audio playback with state management
 * - Proper error handling and resilience
 *
 * Migration from gateway:
 * OLD: TTSManager(context).generateSpeech("Hello", "lennox")
 * NEW: NativeTTSService(context).synthesize("Hello")
 */
class NativeTTSService(
    private val context: Context,
    private val logger: (String) -> Unit = {}
) {
    private val settings = SettingsManager(context)
    private val audioPlayer = TTSAudioPlayer()
    private val tag = "NativeTTSService"

    private var engine: Qwen3TTSEngine? = null
    private var tokenizer: BPETokenizer? = null
    private var isInitialized = false

    // Model paths
    private val modelDirectory: File
        get() = File(context.filesDir, "tts_models")

    private val defaultModelPath: File
        get() = File(modelDirectory, "qwen_tts_2b.gguf")

    private val defaultCodecPath: File
        get() = File(modelDirectory, "codec.gguf")

    /**
     * Initialize the native TTS engine.
     * Loads GGUF models and prepares the neural network for inference.
     */
    suspend fun initialize(): Boolean = withContext(Dispatchers.IO) {
        if (isInitialized) {
            logger("Native TTS already initialized")
            return@withContext true
        }

        try {
            logger("Initializing native Qwen3-TTS engine...")

            // Ensure model directory exists
            if (!modelDirectory.exists()) {
                modelDirectory.mkdirs()
            }

            // Check for model files
            val modelPath = getModelPath()
            val codecPath = getCodecPath()

            if (!modelPath.exists()) {
                logger("ERROR: Model file not found at ${modelPath.absolutePath}")
                logger("Please place GGUF model files in ${modelDirectory.absolutePath}")
                return@withContext false
            }

            // Initialize tokenizer with basic vocabulary
            val vocab = createBasicVocabulary()
            tokenizer = BPETokenizer.create(vocab)

            // Initialize the neural engine
            engine = Qwen3TTSEngine(modelPath.absolutePath, codecPath.absolutePath)
            val initSuccess = engine?.init() ?: false

            if (initSuccess) {
                isInitialized = true
                val config = engine?.getConfig()
                logger("Native TTS initialized successfully")
                logger("Model config: hiddenSize=${config?.hiddenSize}, layers=${config?.numHiddenLayers}")
                logger("Audio: ${config?.audioSampleRate}Hz, ${config?.audioTokenRate} tokens/sec")
            } else {
                logger("ERROR: Failed to initialize Qwen3-TTS engine")
            }

            return@withContext initSuccess
        } catch (e: Exception) {
            Log.e(tag, "Initialization failed: ${e.message}", e)
            logger("ERROR: ${e.message}")
            return@withContext false
        }
    }

    /**
     * Synthesize speech from text using native neural TTS.
     *
     * @param text Input text to synthesize
     * @param voice Voice model identifier (GGUF filename without extension)
     * @param speed Speech speed multiplier (1.0 = normal)
     * @param temperature Sampling temperature for generation
     * @return File containing generated audio (WAV format), or null if failed
     */
    suspend fun synthesize(
        text: String,
        voice: String = "",
        speed: Float = 1.0f,
        temperature: Float = 0.5f
    ): File? = withContext(Dispatchers.IO) {
        if (!isInitialized) {
            val initSuccess = initialize()
            if (!initSuccess) {
                logger("ERROR: Cannot synthesize - engine initialization failed")
                return@withContext null
            }
        }

        if (text.isBlank()) {
            logger("ERROR: Cannot synthesize empty text")
            return@withContext null
        }

        try {
            logger("Synthesizing: ${text.take(30)}... (voice: $voice, speed: $speed)")

            // Use native engine for synthesis
            val audioData = engine?.synthesize(text, speed, temperature)

            if (audioData != null && audioData.isNotEmpty()) {
                // Convert float audio to WAV format
                val wavData = floatToWav(audioData, 24000) // 24kHz sample rate

                // Write to temporary file
                val outputFile = File(context.cacheDir, "tts_native_${System.currentTimeMillis()}.wav")
                FileOutputStream(outputFile).use { it.write(wavData) }

                logger("Generated ${wavData.size} bytes of audio")
                return@withContext outputFile
            } else {
                logger("ERROR: Engine returned empty audio")
                return@withContext null
            }
        } catch (e: Exception) {
            Log.e(tag, "Synthesis failed: ${e.message}", e)
            logger("ERROR: ${e.message}")
            return@withContext null
        }
    }

    /**
     * Get list of available voice models (GGUF files in model directory).
     */
    fun getAvailableVoices(): List<VoiceModel> {
        if (!modelDirectory.exists()) {
            return emptyList()
        }

        return modelDirectory.listFiles()
            ?.filter { it.extension.equals("gguf", ignoreCase = true) }
            ?.map { file ->
                VoiceModel(
                    id = file.nameWithoutExtension,
                    name = file.nameWithoutExtension,
                    path = file.absolutePath,
                    size = file.length(),
                    isDefault = file.name == "qwen_tts_2b.gguf"
                )
            } ?: emptyList()
    }

    /**
     * Check if a specific voice model is available.
     */
    fun hasVoiceModel(voiceId: String): Boolean {
        val voiceFile = File(modelDirectory, "$voiceId.gguf")
        return voiceFile.exists()
    }

    /**
     * Get current engine status.
     */
    fun getStatus(): EngineStatus {
        return EngineStatus(
            isInitialized = isInitialized,
            modelPath = getModelPath().absolutePath,
            codecPath = getCodecPath().absolutePath,
            modelExists = getModelPath().exists(),
            codecExists = getCodecPath().exists(),
            availableVoices = getAvailableVoices().size,
            config = engine?.getConfig()
        )
    }

    /**
     * Play audio file using the audio player.
     */
    fun playAudio(file: File) {
        audioPlayer.play(file)
    }

    /**
     * Stop current audio playback.
     */
    fun stopPlayback() {
        audioPlayer.stop()
    }

    /**
     * Get current audio player state.
     */
    fun getPlaybackState(): AudioPlayerState {
        return audioPlayer.state
    }

    /**
     * Clean up resources.
     */
    fun shutdown() {
        stopPlayback()
        engine?.cleanup()
        engine = null
        tokenizer = null
        isInitialized = false
        logger("Native TTS service shut down")
    }

    // -----------------------------------------------------------------------
    // Private helper methods
    // -----------------------------------------------------------------------

    private fun getModelPath(): File {
        // Use configured voice model or default
        val configuredVoice = settings.selectedVoice
        val customModel = File(modelDirectory, "$configuredVoice.gguf")

        return if (customModel.exists()) {
            customModel
        } else {
            defaultModelPath
        }
    }

    private fun getCodecPath(): File {
        return defaultCodecPath
    }

    private fun createBasicVocabulary(): Map<String, Int> {
        // Create a basic vocabulary for tokenization
        val vocab = mutableMapOf<String, Int>()

        // Add special tokens
        vocab[BPETokenizer.PAD_TOKEN] = 0
        vocab[BPETokenizer.EOS_TOKEN] = 1
        vocab[BPETokenizer.BOS_TOKEN] = 2
        vocab[BPETokenizer.UNK_TOKEN] = 3

        // Add basic characters and common combinations
        var id = 4
        val chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ,.!?;:'\"()-\n"
        for (char in chars) {
            vocab[char.toString()] = id++
        }

        // Add common bigrams
        val commonBigrams = listOf("th", "he", "in", "er", "an", "re", "on", "at", "en", "nd")
        for (bigram in commonBigrams) {
            vocab[bigram] = id++
        }

        return vocab
    }

    private fun floatToWav(audioData: FloatArray, sampleRate: Int): ByteArray {
        val sampleCount = audioData.size
        val byteCount = sampleCount * 2 // 16-bit samples
        val totalSize = 44 + byteCount // WAV header + data

        val wav = ByteArray(totalSize)

        // WAV Header
        // RIFF chunk
        "RIFF".toByteArray().copyInto(wav, 0)
        intToLittleEndianBytes(totalSize - 8).copyInto(wav, 4)
        "WAVE".toByteArray().copyInto(wav, 8)

        // fmt chunk
        "fmt ".toByteArray().copyInto(wav, 12)
        intToLittleEndianBytes(16).copyInto(wav, 16) // PCM chunk size
        shortToLittleEndianBytes(1).copyInto(wav, 20) // Audio format (PCM)
        shortToLittleEndianBytes(1).copyInto(wav, 22) // Channels (mono)
        intToLittleEndianBytes(sampleRate).copyInto(wav, 24) // Sample rate
        intToLittleEndianBytes(sampleRate * 2).copyInto(wav, 28) // Byte rate
        shortToLittleEndianBytes(2).copyInto(wav, 32) // Block align
        shortToLittleEndianBytes(16).copyInto(wav, 34) // Bits per sample

        // data chunk
        "data".toByteArray().copyInto(wav, 36)
        intToLittleEndianBytes(byteCount).copyInto(wav, 40)

        // Audio data (convert float to 16-bit PCM)
        for (i in audioData.indices) {
            val sample = (audioData[i] * 32767f).toInt().coerceIn(-32768, 32767)
            shortToLittleEndianBytes(sample.toShort()).copyInto(wav, 44 + i * 2)
        }

        return wav
    }

    private fun intToLittleEndianBytes(value: Int): ByteArray {
        return byteArrayOf(
            (value and 0xFF).toByte(),
            ((value shr 8) and 0xFF).toByte(),
            ((value shr 16) and 0xFF).toByte(),
            ((value shr 24) and 0xFF).toByte()
        )
    }

    private fun shortToLittleEndianBytes(value: Short): ByteArray {
        return byteArrayOf(
            (value.toInt() and 0xFF).toByte(),
            ((value.toInt() shr 8) and 0xFF).toByte()
        )
    }
}

/**
 * Voice model information.
 */
data class VoiceModel(
    val id: String,
    val name: String,
    val path: String,
    val size: Long,
    val isDefault: Boolean
)

/**
 * Engine status information.
 */
data class EngineStatus(
    val isInitialized: Boolean,
    val modelPath: String,
    val codecPath: String,
    val modelExists: Boolean,
    val codecExists: Boolean,
    val availableVoices: Int,
    val config: Qwen3TTSEngine.Config?
)