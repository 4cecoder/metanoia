package com.bytecats.metanoia

import android.content.Context
import android.content.SharedPreferences
import com.bytecats.metanoia.settings.SettingsManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever

/**
 * Behavioral coverage for SettingsManager. SettingsManager takes an Android
 * Context in its constructor, so we mock Context (Mockito) and back
 * getSharedPreferences with a tiny hand-rolled in-memory fake rather than
 * trying to Mockito-mock the fluent SharedPreferences.Editor chain.
 */
class SettingsManagerTest {

    /** Minimal in-memory fake covering just what SettingsManager calls. */
    private class FakeSharedPreferences : SharedPreferences {
        val backing = mutableMapOf<String, Any?>()

        inner class FakeEditor : SharedPreferences.Editor {
            private val pending = mutableMapOf<String, Any?>()
            override fun putString(key: String?, value: String?): SharedPreferences.Editor {
                pending[key!!] = value; return this
            }
            override fun putStringSet(key: String?, values: MutableSet<String>?): SharedPreferences.Editor {
                pending[key!!] = values; return this
            }
            override fun putInt(key: String?, value: Int): SharedPreferences.Editor {
                pending[key!!] = value; return this
            }
            override fun putLong(key: String?, value: Long): SharedPreferences.Editor {
                pending[key!!] = value; return this
            }
            override fun putFloat(key: String?, value: Float): SharedPreferences.Editor {
                pending[key!!] = value; return this
            }
            override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor {
                pending[key!!] = value; return this
            }
            override fun remove(key: String?): SharedPreferences.Editor {
                pending[key!!] = null; return this
            }
            override fun clear(): SharedPreferences.Editor {
                backing.clear(); return this
            }
            override fun commit(): Boolean {
                apply(); return true
            }
            override fun apply() {
                backing.putAll(pending)
            }
        }

        override fun getAll(): MutableMap<String, *> = backing
        override fun getString(key: String?, defValue: String?): String? =
            backing[key] as? String ?: defValue
        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
            @Suppress("UNCHECKED_CAST") (backing[key] as? MutableSet<String> ?: defValues)
        override fun getInt(key: String?, defValue: Int): Int =
            backing[key] as? Int ?: defValue
        override fun getLong(key: String?, defValue: Long): Long =
            backing[key] as? Long ?: defValue
        override fun getFloat(key: String?, defValue: Float): Float =
            backing[key] as? Float ?: defValue
        override fun getBoolean(key: String?, defValue: Boolean): Boolean =
            backing[key] as? Boolean ?: defValue
        override fun contains(key: String?): Boolean = backing.containsKey(key)
        override fun edit(): SharedPreferences.Editor = FakeEditor()
        override fun registerOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?
        ) {}
        override fun unregisterOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?
        ) {}
    }

    private lateinit var fakePrefs: FakeSharedPreferences
    private lateinit var settings: SettingsManager

    @Before
    fun setUp() {
        fakePrefs = FakeSharedPreferences()
        val context = mock<Context>()
        whenever(context.getSharedPreferences(any(), any())).thenReturn(fakePrefs)
        settings = SettingsManager(context)
    }

    // -------------------------------------------------------------------
    // Defaults
    // -------------------------------------------------------------------

    @Test
    fun defaultsMatchHardcodedValues() {
        assertEquals("192.168.122.2", settings.gatewayIp)
        assertEquals("8000", settings.gatewayPort)
        assertTrue(settings.useGatewayBible)
        assertFalse(settings.useExperimentalTTS)
        assertEquals("lennox", settings.selectedVoice)
        assertTrue(settings.tpuEnabled)
        assertFalse(settings.speakDefinitionsOnTap)
        assertEquals(20, settings.englishFontSize)
        assertEquals(22, settings.ancientFontSize)
        assertTrue(settings.hapticFeedbackEnabled)
        assertEquals("NKJV", settings.bibleGatewayVersion)
        assertFalse(settings.nightlyUpdatesEnabled)
        assertEquals(0L, settings.lastUpdateCheckMillis)
        assertEquals("", settings.dismissedUpdateSha)
    }

    // -------------------------------------------------------------------
    // Round-trip set/get
    // -------------------------------------------------------------------

    @Test
    fun gatewayIpRoundTrips() {
        settings.gatewayIp = "10.0.0.5"
        assertEquals("10.0.0.5", settings.gatewayIp)
    }

    @Test
    fun nightlyUpdatesEnabledRoundTrips() {
        settings.nightlyUpdatesEnabled = true
        assertTrue(settings.nightlyUpdatesEnabled)
        settings.nightlyUpdatesEnabled = false
        assertFalse(settings.nightlyUpdatesEnabled)
    }

    @Test
    fun englishFontSizeRoundTrips() {
        settings.englishFontSize = 28
        assertEquals(28, settings.englishFontSize)
    }

    @Test
    fun lastUpdateCheckMillisRoundTrips() {
        settings.lastUpdateCheckMillis = 1753142400000L
        assertEquals(1753142400000L, settings.lastUpdateCheckMillis)
    }

    @Test
    fun dismissedUpdateShaRoundTrips() {
        settings.dismissedUpdateSha = "a1b2c3d"
        assertEquals("a1b2c3d", settings.dismissedUpdateSha)
    }

    // -------------------------------------------------------------------
    // ttsServerUrl legacy parse-and-delegate
    // -------------------------------------------------------------------

    @Test
    fun ttsServerUrlGetterDelegatesToGatewayUrl() {
        settings.gatewayIp = "1.2.3.4"
        settings.gatewayPort = "9000"
        assertEquals("http://1.2.3.4:9000", settings.ttsServerUrl)
    }

    @Test
    fun ttsServerUrlSetterParsesIpAndPort() {
        settings.ttsServerUrl = "http://1.2.3.4:9000"
        assertEquals("1.2.3.4", settings.gatewayIp)
        assertEquals("9000", settings.gatewayPort)
    }

    @Test
    fun ttsServerUrlSetterParsesHttpsAndTrailingSlash() {
        settings.ttsServerUrl = "https://5.6.7.8:1234/"
        assertEquals("5.6.7.8", settings.gatewayIp)
        assertEquals("1234", settings.gatewayPort)
    }

    @Test
    fun ttsServerUrlSetterHandlesMalformedSingleTokenInput() {
        // No ":" separator at all -- only the IP component is updated, port
        // is left as whatever it already was (this pins the existing
        // documented behavior, not a new requirement).
        settings.gatewayPort = "8000"
        settings.ttsServerUrl = "justahost"
        assertEquals("justahost", settings.gatewayIp)
        assertEquals("8000", settings.gatewayPort)
    }
}
