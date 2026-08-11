package com.bytecats.metanoia.settings

import android.content.Context
import android.content.SharedPreferences

class SettingsManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("metanoia_settings", Context.MODE_PRIVATE)

    // ========================================================================
    // NATIVE TTS CONFIGURATION
    // ========================================================================

    /** Enable/disable native Qwen3-TTS neural synthesis */
    var useNativeTTS: Boolean
        get() = prefs.getBoolean("use_native_tts", true)
        set(value) = prefs.edit().putBoolean("use_native_tts", value).apply()

    /** Selected voice model identifier (GGUF filename without extension) */
    var selectedVoice: String
        get() = prefs.getString("selected_voice", "qwen_tts_2b") ?: "qwen_tts_2b"
        set(value) = prefs.edit().putString("selected_voice", value).apply()

    /** Default speech speed multiplier (1.0 = normal speed) */
    var speechSpeed: Float
        get() = prefs.getFloat("speech_speed", 1.0f)
        set(value) = prefs.edit().putFloat("speech_speed", value.coerceIn(0.5f, 2.0f)).apply()

    /** Speech generation temperature (lower = more deterministic) */
    var speechTemperature: Float
        get() = prefs.getFloat("speech_temperature", 0.5f)
        set(value) = prefs.edit().putFloat("speech_temperature", value.coerceIn(0.1f, 1.0f)).apply()

    /** Custom model directory path (empty = use default app directory) */
    var customModelDirectory: String
        get() = prefs.getString("custom_model_dir", "") ?: ""
        set(value) = prefs.edit().putString("custom_model_dir", value).apply()

    // ========================================================================
    // LEGACY GATEWAY SETTINGS (DEPRECATED)
    // ========================================================================
    // @deprecated All gateway connection settings are deprecated.
    // The native Qwen3-TTS forward pass implementation replaces gateway TTS.
    // See docs/GATEWAY_MIGRATION.md for migration guide.

    @Deprecated("Gateway IP setting is deprecated. Native TTS no longer requires gateway connectivity.", level = DeprecationLevel.WARNING)
    var gatewayIp: String
        get() = prefs.getString("gateway_ip", "192.168.122.2") ?: "192.168.122.2"
        set(value) = prefs.edit().putString("gateway_ip", value).apply()

    @Deprecated("Gateway port setting is deprecated. Native TTS no longer requires gateway connectivity.", level = DeprecationLevel.WARNING)
    var gatewayPort: String
        get() = prefs.getString("gateway_port", "8000") ?: "8000"
        set(value) = prefs.edit().putString("gateway_port", value).apply()

    @Deprecated("Gateway URL is deprecated. Native TTS no longer requires gateway connectivity.", level = DeprecationLevel.WARNING)
    val gatewayUrl: String
        get() = "http://${gatewayIp}:${gatewayPort}"

    /** Legacy compat — delegates to gatewayUrl */
    @Deprecated("Gateway URL is deprecated. Use native Qwen3TTSEngine instead.", level = DeprecationLevel.WARNING)
    var ttsServerUrl: String
        get() = gatewayUrl
        set(value) {
            // Parse "http://ip:port" back into components
            val cleaned = value.removePrefix("http://").removePrefix("https://").trimEnd('/')
            val parts = cleaned.split(":")
            if (parts.size >= 2) {
                gatewayIp = parts[0]
                gatewayPort = parts[1]
            } else if (parts.size == 1 && parts[0].isNotEmpty()) {
                gatewayIp = parts[0]
            }
        }

    @Deprecated("Bible gateway API setting is deprecated. Direct scraping via BibleGatewayScraper is recommended.", level = DeprecationLevel.WARNING)
    var useGatewayBible: Boolean
        get() = prefs.getBoolean("use_gateway_bible", true)
        set(value) = prefs.edit().putBoolean("use_gateway_bible", value).apply()

    // --- Audio & TPU ---
    var tpuEnabled: Boolean
        get() = prefs.getBoolean("tpu_enabled", true)
        set(value) = prefs.edit().putBoolean("tpu_enabled", value).apply()

    var speakDefinitionsOnTap: Boolean
        get() = prefs.getBoolean("speak_defs_on_tap", false)
        set(value) = prefs.edit().putBoolean("speak_defs_on_tap", value).apply()

    // --- Reader UI ---
    var themeMode: String
        get() = prefs.getString("theme_mode", "system") ?: "system"
        set(value) = prefs.edit().putString("theme_mode", value).apply()

    var englishFontSize: Int
        get() = prefs.getInt("english_font_size", 20).coerceIn(10, 48)
        set(value) = prefs.edit().putInt("english_font_size", value.coerceIn(10, 48)).apply()

    var ancientFontSize: Int
        get() = prefs.getInt("ancient_font_size", 22).coerceIn(10, 48)
        set(value) = prefs.edit().putInt("ancient_font_size", value.coerceIn(10, 48)).apply()

    var hapticFeedbackEnabled: Boolean
        get() = prefs.getBoolean("haptic_enabled", true)
        set(value) = prefs.edit().putBoolean("haptic_enabled", value).apply()

    /** Whether the Ethiopian-canon books (testament == "Eth") show up in the
     * book-picker grid. Default true (shown) — this only hides them from
     * that grid selection UI, it does not delete any cached data. */
    var showEthiopianCanon: Boolean
        get() = prefs.getBoolean("show_ethiopian_canon", true)
        set(value) = prefs.edit().putBoolean("show_ethiopian_canon", value).apply()

    /** Whether the deuterocanonical/Apocrypha books (BibleBook.isApocrypha,
     * i.e. Tobit, Judith, Wisdom, Sirach) show up in the book-picker grid.
     * Default true (shown) — this only hides them from that grid selection
     * UI, it does not delete any cached data. Independent of
     * [showEthiopianCanon]: these books are tagged testament == "Old", not
     * "Eth", so the two toggles never overlap. */
    var showApocrypha: Boolean
        get() = prefs.getBoolean("show_apocrypha", true)
        set(value) = prefs.edit().putBoolean("show_apocrypha", value).apply()

    // --- Sync & Data ---
    var bibleGatewayVersion: String
        get() = prefs.getString("gateway_version", "NKJV") ?: "NKJV"
        set(value) = prefs.edit().putString("gateway_version", value).apply()

    var scraperUserAgent: String
        get() = prefs.getString("scraper_user_agent", "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro)") ?: "Mozilla/5.0"
        set(value) = prefs.edit().putString("scraper_user_agent", value).apply()

    // --- Updates ---
    var nightlyUpdatesEnabled: Boolean
        get() = prefs.getBoolean("nightly_updates_enabled", false)
        set(value) = prefs.edit().putBoolean("nightly_updates_enabled", value).apply()

    var lastUpdateCheckMillis: Long
        get() = prefs.getLong("last_update_check_millis", 0L)
        set(value) = prefs.edit().putLong("last_update_check_millis", value).apply()

    var dismissedUpdateSha: String
        get() = prefs.getString("dismissed_update_sha", "") ?: ""
        set(value) = prefs.edit().putString("dismissed_update_sha", value).apply()
}
