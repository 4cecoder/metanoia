package com.bytecats.metanoia.llm

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

enum class AIProvider { LOCAL_TPU, OLLAMA }

class LLMManager(private val context: Context, private val onLog: (String) -> Unit) {
    private var llmInference: LlmInference? = null
    private val client = OkHttpClient()
    
    private val _status = MutableStateFlow("Uninitialized")
    val status: StateFlow<String> = _status
    
    private val _isBusy = MutableStateFlow(false)
    val isBusy: StateFlow<Boolean> = _isBusy

    private val _downloadProgress = MutableStateFlow(0f)
    val downloadProgress: StateFlow<Float> = _downloadProgress

    private val _provider = MutableStateFlow(AIProvider.LOCAL_TPU)
    val provider: StateFlow<AIProvider> = _provider

    val modelFileName = "granite_350m_instruct.bin"
    val modelFile = File(context.filesDir, modelFileName)
    // Official IBM MediaPipe Binary
    val modelUrl = "https://huggingface.co/ibm-granite/granite-3.1-350m-instruct-mediapipe/resolve/main/granite_350m_instruct.bin?download=true"

    var ollamaUrl = "http://192.168.1.100:11434" 
    var ollamaModel = "granite4:350m"

    fun setProvider(p: AIProvider) {
        _provider.value = p
        onLog("SYSTEM: Switched to ${p.name} Engine")
    }

    fun isModelLoaded(): Boolean = llmInference != null
    fun modelExists(): Boolean = modelFile.exists()

    fun loadModel() {
        if (!modelFile.exists()) return
        try {
            onLog("SYSTEM: Binding Granite-4:350M to TPU...")
            llmInference?.close()
            val options = LlmInference.LlmInferenceOptions.builder()
                .setModelPath(modelFile.absolutePath)
                .setMaxTokens(1024)
                .setTemperature(0.7f)
                .build()
            llmInference = LlmInference.createFromOptions(context, options)
            onLog("SYSTEM: Local Engine ONLINE.")
            _status.value = "Ready"
        } catch (e: Exception) {
            onLog("LLM LOAD FAIL: ${e.message}")
            _status.value = "Error"
        }
    }

    suspend fun downloadModel() = withContext(Dispatchers.IO) {
        if (_isBusy.value) return@withContext
        _isBusy.value = true
        _downloadProgress.value = 0.001f
        try {
            onLog("LLM: Syncing 350M Scholar Engine from Cloud...")
            val request = Request.Builder().url(modelUrl).build()
            val response = client.newCall(request).execute()
            if (!response.isSuccessful) throw Exception("HTTP ${response.code}")
            
            val body = response.body ?: throw Exception("Empty body")
            val totalBytes = body.contentLength()
            val input = body.byteStream()
            val output = FileOutputStream(modelFile)
            
            val buffer = ByteArray(65536); var bytesRead: Int; var totalRead: Long = 0
            while (input.read(buffer).also { bytesRead = it } != -1) {
                output.write(buffer, 0, bytesRead)
                totalRead += bytesRead
                if (totalBytes > 0) _downloadProgress.value = totalRead.toFloat() / totalBytes.toFloat()
            }
            output.close(); input.close()
            onLog("LLM: Transfer complete (${totalRead / 1024} KB).")
            withContext(Dispatchers.Main) { 
                _isBusy.value = false
                loadModel() 
            }
        } catch (e: Exception) {
            onLog("LLM ERR: ${e.message}. Check network or use ADB push.")
            _isBusy.value = false
            _downloadProgress.value = 0f
        }
    }

    fun generateResponse(prompt: String): Flow<String> = callbackFlow {
        if (_provider.value == AIProvider.LOCAL_TPU) {
            if (llmInference == null) { trySend("Engine not ready."); close(); return@callbackFlow }
            val fullPrompt = "<|system|>\nYou are Metanoia AI.\n<|user|>\n$prompt\n<|assistant|>\n"
            try {
                val response = llmInference?.generateResponse(fullPrompt) ?: "..."
                response.split(" ").forEach { 
                    kotlinx.coroutines.delay(10)
                    trySend("$it ") 
                }
                close()
            } catch (e: Exception) { trySend("ERR: ${e.message}"); close() }
        } else {
            onLog("OLLAMA: Chatting with $ollamaModel...")
            try {
                val message = JSONObject().apply { put("role", "user"); put("content", prompt) }
                val messages = JSONArray().put(message)
                val json = JSONObject().apply { put("model", ollamaModel); put("messages", messages); put("stream", false) }
                val request = Request.Builder().url("$ollamaUrl/api/chat")
                    .post(json.toString().toRequestBody("application/json".toMediaType())).build()
                val response = withContext(Dispatchers.IO) { client.newCall(request).execute() }
                if (!response.isSuccessful) throw Exception("HTTP ${response.code}")
                val chatResponse = JSONObject(response.body?.string() ?: "{}").getJSONObject("message").optString("content", "")
                chatResponse.split(" ").forEach { kotlinx.coroutines.delay(5); trySend("$it ") }
                close()
            } catch (e: Exception) {
                onLog("OLLAMA ERR: ${e.message}"); trySend("OLLAMA ERR."); close()
            }
        }
        awaitClose {}
    }
}
