package com.bytecats.metanoia.viewmodel

import com.bytecats.metanoia.BuildConfig
import android.app.Application
import android.util.Log
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.bytecats.metanoia.bible.BibleManager
import com.bytecats.metanoia.bible.VerseReference
import com.bytecats.metanoia.models.*
import com.bytecats.metanoia.settings.SettingsManager
import com.bytecats.metanoia.stt.STTManager
import com.bytecats.metanoia.models.RemoteVoice
import com.bytecats.metanoia.tts.TTSManager
import com.bytecats.metanoia.tts.NativeTTSService
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

class MainViewModel(application: Application) : AndroidViewModel(application) {
    private val context = application.applicationContext

    val settingsManager = SettingsManager(context)
    val bibleManager = BibleManager(context)

    // Native TTS service (replaces deprecated gateway system)
    var nativeTTSService: NativeTTSService? = null
    @Deprecated("Use nativeTTSService instead of gateway client", level = DeprecationLevel.WARNING)
    val gateway = bibleManager.gateway //保留用于向后兼容，但不推荐使用
    var ttsManager: TTSManager? = null // 保留用于向后兼容
    var sttManager: STTManager? = null

    val voiceLogs = mutableStateListOf<String>()

    // Voice state (now using GGUF models instead of server voices)
    var availableVoices = mutableStateListOf<com.bytecats.metanoia.tts.VoiceModel>()
    var isInitializingTTS by mutableStateOf(false)

    // Native TTS status
    var isNativeTTSReady by mutableStateOf(false)

    val isRemoteTtsActive: Boolean get() = isNativeTTSReady

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
        viewModelScope.launch {
            try {
                // Initialize native TTS service
                nativeTTSService = NativeTTSService(context) { msg ->
                    voiceLogs.add("[${currentTime()}] $msg")
                }

                // Initialize native TTS engine
                initializeNativeTTS()

                // Initialize other managers
                ttsManager = TTSManager(context) { msg ->
                    voiceLogs.add("[${currentTime()}] $msg")
                }
                sttManager = STTManager(context)

                // Refresh available voices (GGUF models)
                refreshAvailableVoices()

                // Aggressive auto-update when experimental updates enabled:
                // checks immediately on startup, then re-checks hourly
                // while the app is running, and auto-downloads + installs
                // any new build it finds.
                if (settingsManager.nightlyUpdatesEnabled) {
                    startAutoUpdateLoop()
                }
            } catch (e: Exception) {
                Log.e("VM", "Initialization failed: ${e.message}")
                voiceLogs.add("[${currentTime()}] ERROR: ${e.message}")
            }
        }
    }

    private fun currentTime() = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())

    // -----------------------------------------------------------------------
    // Native TTS initialization
    // -----------------------------------------------------------------------

    /**
     * Initialize the native Qwen3-TTS engine.
     * Replaces deprecated gateway connection checks.
     */
    fun initializeNativeTTS() {
        if (isInitializingTTS) return
        isInitializingTTS = true

        viewModelScope.launch {
            voiceLogs.add("[${currentTime()}] Initializing native Qwen3-TTS engine...")
            val success = nativeTTSService?.initialize() ?: false
            isNativeTTSReady = success
            isInitializingTTS = false

            if (success) {
                val status = nativeTTSService?.getStatus()
                voiceLogs.add("[${currentTime()}] Native TTS READY: ${status?.availableVoices} voices available")
            } else {
                voiceLogs.add("[${currentTime()}] Native TTS FAILED - TTS unavailable")
            }
        }
    }

    /**
     * Refresh available voice models (GGUF files).
     * Replaces deprecated server voice discovery.
     */
    fun refreshAvailableVoices() {
        viewModelScope.launch {
            val voices = nativeTTSService?.getAvailableVoices() ?: emptyList()
            availableVoices.clear()
            availableVoices.addAll(voices)
            voiceLogs.add("[${currentTime()}] Found ${voices.size} voice models")
        }
    }

    // -----------------------------------------------------------------------
    // Legacy gateway methods (deprecated - kept for backward compatibility)
    // -----------------------------------------------------------------------

    @Deprecated("Use initializeNativeTTS() instead", level = DeprecationLevel.WARNING)
    fun checkGatewayConnection() {
        initializeNativeTTS()
    }

    @Deprecated("Use initializeNativeTTS() instead", level = DeprecationLevel.WARNING)
    fun testGatewayConnection(onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            val success = nativeTTSService?.initialize() ?: false
            onResult(success)
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

    /**
     * Refresh available voice models (GGUF files).
     * This replaces the deprecated discoverServer() method.
     */
    fun discoverServer() {
        refreshAvailableVoices()
    }

    /**
     * Refresh available voice models (GGUF files).
     * This replaces the deprecated refreshServerVoices() method.
     */
    fun refreshServerVoices() {
        refreshAvailableVoices()
    }

    /**
     * Check if a voice model is available.
     * @param voiceId Voice model identifier (GGUF filename without extension)
     */
    fun hasVoiceModel(voiceId: String): Boolean {
        return nativeTTSService?.hasVoiceModel(voiceId) ?: false
    }

    /**
     * Get native TTS engine status.
     */
    fun getTTSEngineStatus(): com.bytecats.metanoia.tts.EngineStatus? {
        return nativeTTSService?.getStatus()
    }

    // -----------------------------------------------------------------------
    // Legacy voice management methods (deprecated - GGUF models managed as files)
    // -----------------------------------------------------------------------

    @Deprecated("Voice management now uses GGUF model files. Manage voices via file system.", level = DeprecationLevel.WARNING)
    fun deleteServerVoice(key: String) {
        voiceLogs.add("[${currentTime()}] Voice deletion deprecated - manage GGUF files directly")
    }

    @Deprecated("Voice creation now uses GGUF model files. Create voices via VoiceLab.", level = DeprecationLevel.WARNING)
    fun createServerVoice(name: String, text: String) {
        voiceLogs.add("[${currentTime()}] Voice creation deprecated - use VoiceLab for GGUF models")
    }

    @Deprecated("Voice sample upload deprecated - use GGUF model files instead", level = DeprecationLevel.WARNING)
    fun uploadVoiceSample(key: String, file: File) {
        voiceLogs.add("[${currentTime()}] Voice upload deprecated - use GGUF model files instead")
    }

    /**
     * Speak text using custom native Qwen3-TTS neural forward pass engine.
     * Built-in Android TextToSpeech is deprecated in favor of native GGUF synthesis.
     */
    fun speak(text: String) {
        viewModelScope.launch {
            val voice = settingsManager.selectedVoice
            voiceLogs.add("[${currentTime()}] Native Qwen3-TTS forward pass ($voice): ${text.take(20)}...")

            val service = nativeTTSService ?: NativeTTSService(context) { msg ->
                voiceLogs.add("[${currentTime()}] $msg")
            }.also { nativeTTSService = it }

            val audioFile = service.synthesize(text, voice)

            if (audioFile != null && audioFile.exists()) {
                service.playAudio(audioFile)
                if (_narrationState.value.isPlaying) advanceNarration()
            } else {
                voiceLogs.add("[${currentTime()}] ERROR: Native Qwen3-TTS synthesis failed. System TTS deprecated.")
            }
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
        nativeTTSService?.stopPlayback()
        _narrationState.value = NarrationState(isPlaying = false)
    }

    override fun onCleared() {
        nativeTTSService?.shutdown()
        nativeTTSService = null

        ttsManager?.shutdown()
        ttsManager = null

        super.onCleared()
    }
}
