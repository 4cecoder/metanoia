package com.bytecats.metanoia.settings

import android.content.Context
import android.content.SharedPreferences

class SettingsManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("metanoia_settings", Context.MODE_PRIVATE)

    // --- Audio & TPU ---
    var useExperimentalTTS: Boolean
        get() = prefs.getBoolean("use_experimental_tts", false)
        set(value) = prefs.edit().putBoolean("use_experimental_tts", value).apply()

    var selectedVoice: String
        get() = prefs.getString("selected_voice", "John Lennox") ?: "John Lennox"
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

    // --- Sync & Data ---
    var bibleGatewayVersion: String
        get() = prefs.getString("gateway_version", "NKJV") ?: "NKJV"
        set(value) = prefs.edit().putString("gateway_version", value).apply()

    var scraperUserAgent: String
        get() = prefs.getString("scraper_user_agent", "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro)") ?: "Mozilla/5.0"
        set(value) = prefs.edit().putString("scraper_user_agent", value).apply()
}
