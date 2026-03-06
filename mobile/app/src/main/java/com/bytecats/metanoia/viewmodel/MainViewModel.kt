package com.bytecats.metanoia.viewmodel

import android.app.Application
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.bytecats.metanoia.bible.BibleManager
import com.bytecats.metanoia.llm.LLMManager
import com.bytecats.metanoia.models.*
import com.bytecats.metanoia.settings.SettingsManager
import com.bytecats.metanoia.tts.RemoteVoice
import com.bytecats.metanoia.tts.TTSManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

data class NarrationState(
    val isPlaying: Boolean = false,
    val currentVerse: Int = -1,
    val queue: List<Pair<Int, String>> = emptyList()
)

class MainViewModel(application: Application) : AndroidViewModel(application), TextToSpeech.OnInitListener {
    private val context = application.applicationContext
    
    val settingsManager = SettingsManager(context)
    val bibleManager = BibleManager(context)
    var ttsManager: TTSManager? = null
    var llmManager: LLMManager? = null
    private var systemTts: TextToSpeech? = null

    val voiceLogs = mutableStateListOf<String>()
    val aiLogs = mutableStateListOf<String>()
    
    // Detailed voice state
    var serverVoices = mutableStateListOf<RemoteVoice>()
    var isDiscovering by mutableStateOf(false)
    
    private val _narrationState = mutableStateOf(NarrationState())
    val narrationState: State<NarrationState> = _narrationState

    init {
        systemTts = TextToSpeech(context, this)
        systemTts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String?) {}
            override fun onDone(id: String?) {
                if (_narrationState.value.isPlaying) {
                    viewModelScope.launch { advanceNarration() }
                }
            }
            override fun onError(id: String?) {}
        })

        viewModelScope.launch {
            try {
                ttsManager = TTSManager(context) { msg -> 
                    voiceLogs.add("[${currentTime()}] $msg")
                }
                llmManager = LLMManager(context) { msg -> 
                    aiLogs.add("[${currentTime()}] $msg")
                }
                
                // Initial load
                refreshServerVoices()
            } catch (e: Exception) {
                Log.e("VM", "Hardware fail: ${e.message}")
            }
        }
    }

    private fun currentTime() = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) systemTts?.language = Locale.US
    }

    fun discoverServer() {
        if (isDiscovering) return
        isDiscovering = true
        viewModelScope.launch {
            ttsManager?.discoverServer()?.let { url ->
                settingsManager.ttsServerUrl = url
                refreshServerVoices()
            }
            isDiscovering = false
        }
    }

    fun refreshServerVoices() {
        viewModelScope.launch {
            val voices = ttsManager?.fetchFullStatus() ?: emptyList()
            serverVoices.clear()
            serverVoices.addAll(voices)
        }
    }

    fun deleteServerVoice(key: String) {
        viewModelScope.launch {
            if (ttsManager?.deleteVoice(key) == true) {
                voiceLogs.add("[${currentTime()}] Voice '$key' deleted.")
                refreshServerVoices()
            }
        }
    }

    fun createServerVoice(name: String, text: String) {
        viewModelScope.launch {
            if (ttsManager?.upsertVoice(name, text) == true) {
                voiceLogs.add("[${currentTime()}] Voice '$name' created.")
                refreshServerVoices()
            }
        }
    }

    fun uploadVoiceSample(key: String, file: File) {
        viewModelScope.launch {
            if (ttsManager?.uploadSample(key, file) == true) {
                voiceLogs.add("[${currentTime()}] Audio for '$key' updated.")
                refreshServerVoices()
            }
        }
    }

    fun speak(text: String) {
        if (settingsManager.useExperimentalTTS && ttsManager != null) {
            viewModelScope.launch {
                val voice = settingsManager.selectedVoice
                voiceLogs.add("[${currentTime()}] Synthesis request ($voice): ${text.take(15)}...")
                
                ttsManager?.generateSpeech(text, voice)?.let { file ->
                    ttsManager?.playAudio(file)
                    if (_narrationState.value.isPlaying) advanceNarration()
                } ?: run {
                    val url = settingsManager.ttsServerUrl
                    voiceLogs.add("[${currentTime()}] ERROR: Remote engine fail at $url. Check server or IP.")
                    systemTts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "metanoia_utterance")
                }
            }
        } else {
            systemTts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "metanoia_utterance")
        }
    }

    fun startChapterNarration(queue: List<Pair<Int, String>>) {
        if (queue.isEmpty()) return
        _narrationState.value = NarrationState(isPlaying = true, currentVerse = queue.first().first, queue = queue)
        narrateCurrentVerse()
    }

    private fun narrateCurrentVerse() {
        val verse = _narrationState.value.queue.find { it.first == _narrationState.value.currentVerse }
        verse?.let { speak(it.second) }
    }

    private suspend fun advanceNarration() {
        val currentIndex = _narrationState.value.queue.indexOfFirst { it.first == _narrationState.value.currentVerse }
        if (currentIndex != -1 && currentIndex < _narrationState.value.queue.size - 1) {
            val nV = _narrationState.value.queue[currentIndex + 1]
            _narrationState.value = _narrationState.value.copy(currentVerse = nV.first)
            narrateCurrentVerse()
        } else {
            stopNarration()
        }
    }

    fun stopNarration() {
        systemTts?.stop()
        _narrationState.value = NarrationState(isPlaying = false)
    }

    override fun onCleared() {
        systemTts?.stop()
        systemTts?.shutdown()
        super.onCleared()
    }
}
