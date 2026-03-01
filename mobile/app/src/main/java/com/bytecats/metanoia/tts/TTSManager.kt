package com.bytecats.metanoia.tts

import android.content.Context
import ai.onnxruntime.*
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.AudioManager
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.nio.channels.FileChannel
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import android.util.Log
import org.json.JSONObject
import kotlin.math.abs

class TTSManager(private val context: Context, private val logger: (String) -> Unit) {
    private val TAG = "TTSManager"
    private var ortEnv: OrtEnvironment = OrtEnvironment.getEnvironment()
    private var talkerSession: OrtSession? = null
    private var codePredictorSession: OrtSession? = null
    private var vocoderSession: OrtSession? = null
    
    private val cacheDir: File = File(context.cacheDir, "tts_cache").apply { mkdirs() }
    private val modelDir: File = File(context.filesDir, "models").apply { mkdirs() }
    
    private var vocab: Map<String, Int> = emptyMap()
    private var reverseVocab: Map<Int, String> = emptyMap()
    private var embeddingChannel: FileChannel? = null

    init {
        loadModels()
    }

    fun clearCache() {
        cacheDir.listFiles()?.forEach { it.delete() }
        logger("Cache cleared.")
    }

    private fun loadModels() {
        try {
            logger("Engine Booting...")
            val tpuOptions = OrtSession.SessionOptions().apply { addNnapi() }
            val cpuOptions = OrtSession.SessionOptions().apply { setIntraOpNumThreads(4) }

            val talkerFile = File(modelDir, "talker_prefill.onnx")
            val cpFile = File(modelDir, "code_predictor.onnx")
            val vocoderFile = File(modelDir, "vocoder.onnx")
            val vocabFile = File(modelDir, "vocab.json")
            val embedFile = File(modelDir, "text_embedding.npy")

            if (!talkerFile.exists()) {
                logger("Models missing.")
                return
            }

            val vocabJson = JSONObject(vocabFile.readText())
            val tempVocab = mutableMapOf<String, Int>()
            val tempRevVocab = mutableMapOf<Int, String>()
            vocabJson.keys().forEach { 
                val id = vocabJson.getInt(it)
                tempVocab[it] = id
                tempRevVocab[id] = it
            }
            vocab = tempVocab
            reverseVocab = tempRevVocab
            embeddingChannel = RandomAccessFile(embedFile, "r").channel

            talkerSession = ortEnv.createSession(talkerFile.absolutePath, tpuOptions)
            codePredictorSession = ortEnv.createSession(cpFile.absolutePath, cpuOptions)
            vocoderSession = ortEnv.createSession(vocoderFile.absolutePath, tpuOptions)
            
            logger("TPU Engine Online (24kHz Mono).")
        } catch (e: Exception) {
            logger("LOAD FAIL: ${e.message}")
        }
    }

    suspend fun generateSpeech(text: String, voice: String): File? = withContext(Dispatchers.Default) {
        val cleanText = text.trim()
        val cacheKey = md5("$cleanText|$voice")
        val cacheFile = File(cacheDir, "tts_$cacheKey.wav")

        if (cacheFile.exists() && cacheFile.length() > 44) return@withContext cacheFile
        if (talkerSession == null) return@withContext null

        try {
            logger("Step 1: Text Tokenization...")
            val tokens = qwenTokenize(cleanText)
            val seqLen = tokens.size.toLong()
            val embeds = getEmbeddings(tokens)
            
            val tokenNames = tokens.map { reverseVocab[it] ?: "[$it]" }.joinToString("|")
            logger("Tokens: $tokenNames")
            
            // --- Step 1: Text Encoding ---
            val talkerInputs = mapOf(
                "inputs_embeds" to createFloatTensor(embeds, longArrayOf(1, seqLen, 1024)),
                "attention_mask" to createLongTensor(LongArray(seqLen.toInt()) { 1L }, longArrayOf(1, seqLen)),
                "position_ids" to createLongTensor(LongArray(3 * seqLen.toInt()) { (it % seqLen).toLong() }, longArrayOf(3, 1, seqLen))
            )

            logger("Step 2: backbone features...")
            val talkerResults = talkerSession?.run(talkerInputs)
            val hiddenStatesTensor = talkerResults?.get(1) as OnnxTensor 
            val hiddenBuffer = hiddenStatesTensor.floatBuffer
            val fullHidden = FloatArray(hiddenBuffer.capacity())
            hiddenBuffer.get(fullHidden)
            
            // --- Step 2: Temporal Upsampling (Solving the Choppiness) ---
            // Qwen3-TTS vocoder is 12Hz. We need ~200 audio frames per text token 
            // to achieve a natural speaking rate.
            val framesPerToken = 100 
            val numFrames = (seqLen * framesPerToken).toInt().coerceIn(100, 400)
            val fullCodes = LongArray(1 * 16 * numFrames)
            
            logger("Step 3: Neural Voice Synthesis ($numFrames frames)...")
            
            for (t in 0 until numFrames) {
                val tokenIdx = (t / framesPerToken).coerceAtMost(seqLen.toInt() - 1)
                val currentHidden = fullHidden.sliceArray((tokenIdx * 1024) until ((tokenIdx + 1) * 1024))
                
                // Prediction for 16 hierarchical codebooks
                val frameCodes = LongArray(16)
                
                // Seat group 0 from Backbone features
                frameCodes[0] = (abs(currentHidden[0]) * 1000).toLong() % 2048
                
                for (step in 0 until 15) {
                    val cpInputs = mapOf(
                        "inputs_embeds" to createFloatTensor(currentHidden, longArrayOf(1, 1, 1024)),
                        "generation_steps" to createLongTensor(longArrayOf(step.toLong()), longArrayOf(1)),
                        "past_keys" to createFloatTensor(FloatArray(0), longArrayOf(5, 1, 8, 0, 128)),
                        "past_values" to createFloatTensor(FloatArray(0), longArrayOf(5, 1, 8, 0, 128))
                    )
                    val cpResults = codePredictorSession?.run(cpInputs)
                    val cpLogits = (cpResults?.get(0) as OnnxTensor).floatBuffer.array()
                    frameCodes[step + 1] = argmax(cpLogits).toLong()
                }
                
                for (g in 0 until 16) {
                    fullCodes[g * numFrames + t] = frameCodes[g]
                }
                if (t % 50 == 0) logger("Frame $t / $numFrames...")
            }

            logger("Step 4: Vocoding...")
            val vocoderInputs = mapOf(
                "codes" to createLongTensor(fullCodes, longArrayOf(1, 16, numFrames.toLong()))
            )

            val vocoderResults = vocoderSession?.run(vocoderInputs)
            val audioData = (vocoderResults?.get(0) as OnnxTensor).floatBuffer.array()

            saveAsWav(cacheFile, audioData, 24000)
            logger("DONE: Playback Ready.")
            cacheFile
        } catch (e: Exception) {
            logger("PIPELINE FAIL: ${e.message}")
            null
        }
    }

    private fun qwenTokenize(text: String): IntArray {
        val tokens = mutableListOf<Int>()
        var i = 0
        while (i < text.length) {
            var found = false
            for (len in (text.length - i) downTo 1) {
                val sub = text.substring(i, i + len)
                val formatted = if (i == 0 || text[i-1] == ' ') sub.replace(" ", "Ġ") else sub
                if (vocab.containsKey(formatted)) {
                    tokens.add(vocab[formatted]!!)
                    i += len; found = true; break
                }
            }
            if (!found) { tokens.add(vocab[text[i].toString()] ?: 0); i++ }
        }
        return tokens.toIntArray()
    }

    private fun createFloatTensor(data: FloatArray, shape: LongArray): OnnxTensor {
        val buffer = ByteBuffer.allocateDirect(data.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        buffer.put(data); buffer.position(0)
        return OnnxTensor.createTensor(ortEnv, buffer, shape)
    }

    private fun createLongTensor(data: LongArray, shape: LongArray): OnnxTensor {
        val buffer = ByteBuffer.allocateDirect(data.size * 8).order(ByteOrder.nativeOrder()).asLongBuffer()
        buffer.put(data); buffer.position(0)
        return OnnxTensor.createTensor(ortEnv, buffer, shape)
    }

    private fun argmax(probs: FloatArray): Int {
        var maxIdx = 0; var maxVal = Float.NEGATIVE_INFINITY
        for (i in probs.indices) { if (probs[i] > maxVal) { maxVal = probs[i]; maxIdx = i } }
        return maxIdx
    }

    private fun getEmbeddings(tokens: IntArray): FloatArray {
        val hiddenSize = 1024
        val result = FloatArray(tokens.size * hiddenSize)
        val buffer = ByteBuffer.allocate(hiddenSize * 4).order(ByteOrder.LITTLE_ENDIAN)
        tokens.forEachIndexed { i, token ->
            val position = 128L + (token.toLong() * hiddenSize * 4)
            buffer.clear()
            embeddingChannel?.read(buffer, position)
            buffer.flip()
            if (buffer.remaining() >= hiddenSize * 4) {
                for (h in 0 until hiddenSize) result[i * hiddenSize + h] = buffer.float
            }
        }
        return result
    }

    private fun md5(input: String): String {
        val md = MessageDigest.getInstance("MD5")
        return md.digest(input.toByteArray()).joinToString("") { "%02x".format(it) }
    }

    private fun saveAsWav(file: File, data: FloatArray, sampleRate: Int) {
        var maxAmp = 0.0001f
        for (f in data) { if (abs(f) > maxAmp) maxAmp = abs(f) }
        val bytes = ByteBuffer.allocate(44 + data.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        bytes.put("RIFF".toByteArray()); bytes.putInt(36 + data.size * 2); bytes.put("WAVE".toByteArray())
        bytes.put("fmt ".toByteArray()); bytes.putInt(16); bytes.putShort(1); bytes.putShort(1)
        bytes.putInt(sampleRate); bytes.putInt(sampleRate * 2); bytes.putShort(2); bytes.putShort(16)
        bytes.put("data".toByteArray()); bytes.putInt(data.size * 2)
        for (f in data) bytes.putShort(((f / maxAmp) * 32760).toInt().toShort())
        file.writeBytes(bytes.array())
    }

    fun playAudio(file: File) {
        val bytes = file.readBytes()
        if (bytes.size < 44) return
        val pcmData = bytes.sliceArray(44 until bytes.size)
        val track = AudioTrack.Builder()
            .setAudioAttributes(android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
                .build())
            .setAudioFormat(AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(24000)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build())
            .setBufferSizeInBytes(pcmData.size)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
        track.write(pcmData, 0, pcmData.size)
        track.play()
    }
}
