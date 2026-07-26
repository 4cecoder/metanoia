package com.bytecats.metanoia.viewmodel

import com.bytecats.metanoia.BuildConfig
import android.app.Application
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.bytecats.metanoia.bible.BibleManager
import com.bytecats.metanoia.bible.VerseReference
import com.bytecats.metanoia.gateway.GatewayClient
import com.bytecats.metanoia.models.*
import com.bytecats.metanoia.settings.SettingsManager
import com.bytecats.metanoia.stt.STTManager
import com.bytecats.metanoia.models.RemoteVoice
import com.bytecats.metanoia.tts.TTSManager
import com.bytecats.metanoia.update.NightlyUpdateInfo
import com.bytecats.metanoia.update.UpdateChecker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.bytecats.metanoia.update.ApkInstaller
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

data class NarrationState(
    val isPlaying: Boolean = false,
    val currentVerse: Int = -1,
    val queue: List<Verse> = emptyList()
)

class MainViewModel(application: Application) : AndroidViewModel(application), TextToSpeech.OnInitListener {
    private val context = application.applicationContext

    val settingsManager = SettingsManager(context)
    val bibleManager = BibleManager(context)
    var ttsManager: TTSManager? = null
    var sttManager: STTManager? = null
    var gateway: GatewayClient? = null
    private var systemTts: TextToSpeech? = null

    val voiceLogs = mutableStateListOf<String>()

    // Detailed voice state
    var serverVoices = mutableStateListOf<RemoteVoice>()
    var isDiscovering by mutableStateOf(false)

    // Gateway status
    var gatewayOnline by mutableStateOf(false)
    var isTestingGateway by mutableStateOf(false)

    val isRemoteTtsActive: Boolean get() = settingsManager.useExperimentalTTS && gatewayOnline

    private val _narrationState = mutableStateOf(NarrationState())
    val narrationState: State<NarrationState> = _narrationState

    // Nightly/experimental update notice (opt-in, throttled — see checkForNightlyUpdateIfDue)
    val availableUpdate = mutableStateOf<NightlyUpdateInfo?>(null)

    // Set by MainActivity when a deep link (metanoia://bible/... or an
    // https App Link) resolves to a specific passage — see
    // com.bytecats.metanoia.bible.DeepLink and docs/ANDROID_DEEP_LINKS.md.
    // BibleScreen consumes-and-clears this once it's acted on it, so
    // navigating back to Bible normally afterward doesn't re-trigger the
    // same jump.
    var pendingDeepLink by mutableStateOf<VerseReference?>(null)

    init {
        gateway = bibleManager.gateway

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
                sttManager = STTManager(context)

                // Check gateway on startup
                checkGatewayConnection()

                // Initial load
                refreshServerVoices()

                // Aggressive auto-update when experimental updates enabled:
                // checks immediately on startup, then re-checks hourly
                // while the app is running, and auto-downloads + installs
                // any new build it finds.
                if (settingsManager.nightlyUpdatesEnabled) {
                    startAutoUpdateLoop()
                }
            } catch (e: Exception) {
                Log.e("VM", "Hardware fail: ${e.message}")
            }
        }
    }

    private fun currentTime() = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) systemTts?.language = Locale.US
    }

    // -----------------------------------------------------------------------
    // Gateway connection
    // -----------------------------------------------------------------------

    fun checkGatewayConnection() {
        viewModelScope.launch {
            isTestingGateway = true
            gatewayOnline = withContext(Dispatchers.IO) {
                gateway?.health() ?: false
            }
            isTestingGateway = false
            voiceLogs.add("[${currentTime()}] Gateway ${settingsManager.gatewayUrl}: ${if (gatewayOnline) "ONLINE" else "OFFLINE"}")
        }
    }

    fun testGatewayConnection(onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            isTestingGateway = true
            val result = withContext(Dispatchers.IO) {
                gateway?.health() ?: false
            }
            gatewayOnline = result
            isTestingGateway = false
            onResult(result)
        }
    }

    // -----------------------------------------------------------------------
    // Auto-update (aggressive — immediate on startup + hourly loop)
    // -----------------------------------------------------------------------

    /**
     * Launches a background coroutine that checks for updates immediately,
     * then re-checks every hour while the app is alive. When `nightlyUpdatesEnabled`
     * is on, this runs continuously — no 24h throttle, no manual button needed.
     */
    private fun startAutoUpdateLoop() {
        viewModelScope.launch {
            while (true) {
                performAutoUpdate()
                delay(60 * 60 * 1000L) // every hour
            }
        }
    }

    /**
     * Single auto-update tick: fetches the latest release, auto-downloads
     * and installs if a newer build is found. Silently retries on failure.
     */
    private suspend fun performAutoUpdate() {
        try {
            val result = withContext(Dispatchers.IO) {
                UpdateChecker.fetchLatest()
            }
            settingsManager.lastUpdateCheckMillis = System.currentTimeMillis()

            val isAvail = result != null &&
                result.commitSha != settingsManager.dismissedUpdateSha &&
                result.downloadUrl != null &&
                UpdateChecker.isUpdateAvailable(BuildConfig.GIT_COMMIT_SHA, result)

            if (isAvail) {
                availableUpdate.value = result
                Log.i("VM", "Auto-update: ${result!!.commitSha?.take(7)} available, downloading...")

                val apk = withContext(Dispatchers.IO) {
                    ApkInstaller.download(getApplication(), result.downloadUrl!!)
                }
                if (apk != null) {
                    Log.i("VM", "Auto-update: downloaded, launching installer...")
                    ApkInstaller.install(getApplication(), apk)
                    settingsManager.dismissedUpdateSha = result.commitSha ?: ""
                    availableUpdate.value = null
                } else {
                    Log.w("VM", "Auto-update: download failed, will retry next cycle.")
                }
            }
        } catch (e: Exception) {
            Log.w("VM", "Auto-update tick failed: ${e.message}")
        }
    }

    fun dismissAvailableUpdate() {
        settingsManager.dismissedUpdateSha = availableUpdate.value?.commitSha ?: ""
        availableUpdate.value = null
    }

    // -----------------------------------------------------------------------
    // TTS / Voice
    // -----------------------------------------------------------------------

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
                    val url = settingsManager.gatewayUrl
                    voiceLogs.add("[${currentTime()}] ERROR: Remote engine fail at $url. Check server or IP.")
                    systemTts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "metanoia_utterance")
                }
            }
        } else {
            systemTts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "metanoia_utterance")
        }
    }

    // -----------------------------------------------------------------------
    // STT (Speech-to-Text)
    // -----------------------------------------------------------------------

    fun transcribeAudio(file: File, onResult: (String?) -> Unit) {
        viewModelScope.launch {
            val text = withContext(Dispatchers.IO) {
                sttManager?.transcribe(file)
            }
            onResult(text)
        }
    }

    // -----------------------------------------------------------------------
    // Narration
    // -----------------------------------------------------------------------

    fun startChapterNarration(queue: List<Verse>) {
        if (queue.isEmpty()) return
        _narrationState.value = NarrationState(isPlaying = true, currentVerse = queue.first().number, queue = queue)
        narrateCurrentVerse()
    }

    private fun narrateCurrentVerse() {
        val verse = _narrationState.value.queue.find { it.number == _narrationState.value.currentVerse }
        verse?.let { speak(it.text) }
    }

    private suspend fun advanceNarration() {
        val currentIndex = _narrationState.value.queue.indexOfFirst { it.number == _narrationState.value.currentVerse }
        if (currentIndex != -1 && currentIndex < _narrationState.value.queue.size - 1) {
            val nV = _narrationState.value.queue[currentIndex + 1]
            _narrationState.value = _narrationState.value.copy(currentVerse = nV.number)
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
