package com.bytecats.metanoia.settings

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class SettingsManagerTest {

    private lateinit var settingsManager: SettingsManager

    @Before
    fun setup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        // Clear prefs before each test
        context.getSharedPreferences("metanoia_settings", Context.MODE_PRIVATE).edit().clear().apply()
        settingsManager = SettingsManager(context)
    }

    @Test
    fun testThemePersistence() {
        assertEquals("system", settingsManager.themeMode)
        
        settingsManager.themeMode = "dark"
        assertEquals("dark", settingsManager.themeMode)
        
        settingsManager.themeMode = "light"
        assertEquals("light", settingsManager.themeMode)
    }

    @Test
    fun testFontScaleBounds() {
        // Initial defaults
        assertTrue(settingsManager.englishFontSize in 10..48)
        assertTrue(settingsManager.ancientFontSize in 10..48)
        
        // Test lower bound
        settingsManager.englishFontSize = 5
        assertEquals(10, settingsManager.englishFontSize)
        
        // Test upper bound
        settingsManager.englishFontSize = 60
        assertEquals(48, settingsManager.englishFontSize)
        
        // Test valid value
        settingsManager.englishFontSize = 25
        assertEquals(25, settingsManager.englishFontSize)

        // Same for ancientFontSize
        settingsManager.ancientFontSize = 8
        assertEquals(10, settingsManager.ancientFontSize)
        
        settingsManager.ancientFontSize = 55
        assertEquals(48, settingsManager.ancientFontSize)
        
        settingsManager.ancientFontSize = 30
        assertEquals(30, settingsManager.ancientFontSize)
    }

    @Test
    fun testCanonVisibilityDefaults() {
        // By default both should be true
        assertTrue(settingsManager.showEthiopianCanon)
        assertTrue(settingsManager.showApocrypha)
        
        // Modifying one shouldn't affect the other
        settingsManager.showEthiopianCanon = false
        assertFalse(settingsManager.showEthiopianCanon)
        assertTrue(settingsManager.showApocrypha)
        
        settingsManager.showApocrypha = false
        assertFalse(settingsManager.showApocrypha)
    }
}
