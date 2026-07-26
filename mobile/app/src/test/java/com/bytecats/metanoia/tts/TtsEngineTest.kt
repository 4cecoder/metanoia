package com.bytecats.metanoia.tts

import com.bytecats.metanoia.models.RemoteVoice
import com.bytecats.metanoia.models.TtsRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class TtsEngineTest {

    @Test
    fun testRemoteVoiceDataClass() {
        val voice = RemoteVoice("af_nicole", "Nicole", true, "kokoro")
        assertEquals("af_nicole", voice.key)
        assertEquals("Nicole", voice.displayName)
        assertEquals(true, voice.exists)
    }

    @Test
    fun testTtsRequestDefaults() {
        val req = TtsRequest("Hello world", "af_nicole")
        assertEquals("Hello world", req.text)
        assertEquals("af_nicole", req.voice)
        assertEquals(1.0f, req.speed, 0.001f)
        assertEquals("speedy", req.mode)
    }

    @Test
    fun testTtsRequestCustomValues() {
        val req = TtsRequest("Test", "am_lennox", speed = 1.5f, mode = "quality")
        assertEquals(1.5f, req.speed, 0.001f)
        assertEquals("quality", req.mode)
    }
}
