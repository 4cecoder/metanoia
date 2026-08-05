package com.bytecats.metanoia.tts

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class TtsAudioResilienceTest {

    @Test
    fun `initial state is IDLE`() {
        val player = TTSAudioPlayer()
        assertEquals(AudioPlayerState.IDLE, player.state)
    }

    @Test
    fun `stop from IDLE remains IDLE`() {
        val player = TTSAudioPlayer()
        player.stop()
        assertEquals(AudioPlayerState.IDLE, player.state)
    }
    
    @Test
    fun `play non-existent file sets ERROR state via playPcmSafe`() {
        val player = TTSAudioPlayer()
        val missingFile = File("does_not_exist.wav")
        
        // This will try MediaPlayer, throw Exception, catch it, and then playPcmSafe will throw when reading bytes
        player.play(missingFile)
        
        assertEquals(AudioPlayerState.ERROR, player.state)
    }

    @Test
    fun `play invalid small file sets ERROR state`() {
        val player = TTSAudioPlayer()
        val invalidFile = File.createTempFile("invalid", ".wav")
        invalidFile.writeText("short")
        
        player.play(invalidFile)
        
        assertEquals(AudioPlayerState.ERROR, player.state)
        invalidFile.delete()
    }
}
