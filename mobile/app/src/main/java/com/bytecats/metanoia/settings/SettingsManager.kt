package com.bytecats.metanoia.settings

import android.content.Context
import android.content.SharedPreferences

class SettingsManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("metanoia_settings", Context.MODE_PRIVATE)

    // --- Gateway Connection ---
    var gatewayIp: String
        get() = prefs.getString("gateway_ip", "192.168.122.2") ?: "192.168.122.2"
        set(value) = prefs.edit().putString("gateway_ip", value).apply()

    var gatewayPort: String
        get() = prefs.getString("gateway_port", "8000") ?: "8000"
        set(value) = prefs.edit().putString("gateway_port", value).apply()

    val gatewayUrl: String
        get() = "http://${gatewayIp}:${gatewayPort}"

    /** Legacy compat — delegates to gatewayUrl */
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

    var useGatewayBible: Boolean
        get() = prefs.getBoolean("use_gateway_bible", true)
        set(value) = prefs.edit().putBoolean("use_gateway_bible", value).apply()

    // --- Audio & TPU ---
    var useExperimentalTTS: Boolean
        get() = prefs.getBoolean("use_experimental_tts", false)
        set(value) = prefs.edit().putBoolean("use_experimental_tts", value).apply()

    var selectedVoice: String
        get() = prefs.getString("selected_voice", "lennox") ?: "lennox"
        set(value) = prefs.edit().putString("selected_voice", value).apply()

    var tpuEnabled: Boolean
        get() = prefs.getBoolean("tpu_enabled", true)
        set(value) = prefs.edit().putBoolean("tpu_enabled", value).apply()

    var speakDefinitionsOnTap: Boolean
        get() = prefs.getBoolean("speak_defs_on_tap", false)
        set(value) = prefs.edit().putBoolean("speak_defs_on_tap", value).apply()

    // --- Reader UI ---
    var englishFontSize: Int
        get() = prefs.getInt("english_font_size", 20)
        set(value) = prefs.edit().putInt("english_font_size", value).apply()

    var ancientFontSize: Int
        get() = prefs.getInt("ancient_font_size", 22)
        set(value) = prefs.edit().putInt("ancient_font_size", value).apply()

    var hapticFeedbackEnabled: Boolean
        get() = prefs.getBoolean("haptic_enabled", true)
        set(value) = prefs.edit().putBoolean("haptic_enabled", value).apply()

    /** Whether the Ethiopian-canon books (testament == "Eth") show up in the
     * book-picker grid. Default true (shown) — this only hides them from
     * that grid selection UI, it does not delete any cached data. */
    var showEthiopianCanon: Boolean
        get() = prefs.getBoolean("show_ethiopian_canon", true)
        set(value) = prefs.edit().putBoolean("show_ethiopian_canon", value).apply()

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
