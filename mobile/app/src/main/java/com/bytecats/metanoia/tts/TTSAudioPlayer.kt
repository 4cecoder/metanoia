package com.bytecats.metanoia.tts

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaPlayer
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicReference

/**
 * Audio player state for TTS playback.
 */
enum class AudioPlayerState {
    /** Player is idle and ready to play */
    IDLE,
    /** Currently playing audio */
    PLAYING,
    /** Playback was stopped */
    STOPPED,
    /** An error occurred during playback */
    ERROR
}

/**
 * TTS audio player - handles playback of generated speech audio.
 *
 * Supports both MediaPlayer (for WAV files) and AudioTrack (for PCM audio),
 * with automatic fallback and state management.
 */
class TTSAudioPlayer {
    private var mediaPlayer: MediaPlayer? = null
    private var audioTrack: AudioTrack? = null
    private val tag = "TTSAudioPlayer"
    
    private val _state = AtomicReference(AudioPlayerState.IDLE)
    /** Current playback state (thread-safe) */
    val state: AudioPlayerState get() = _state.get()

    /**
     * Play audio from a file.
     * Automatically handles WAV file playback via MediaPlayer,
     * with fallback to PCM playback if MediaPlayer fails.
     *
     * @param file Audio file to play (WAV format recommended)
     */
    fun play(file: File) {
        stop()
        try {
            mediaPlayer = MediaPlayer().apply {
                setDataSource(file.absolutePath)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                setOnCompletionListener {
                    _state.set(AudioPlayerState.IDLE)
                }
                setOnErrorListener { _, what, extra ->
                    Log.e(tag, "MediaPlayer error: what=$what extra=$extra")
                    _state.set(AudioPlayerState.ERROR)
                    true
                }
                prepare()
                _state.set(AudioPlayerState.PLAYING)
                start()
            }
        } catch (e: Exception) {
            Log.e(tag, "playAudio failed: ${e.message}")
            releaseMediaPlayer()
            playPcmSafe(file)
        }
    }

    /**
     * Stop current playback and reset state.
     */
    fun stop() {
        val currentState = _state.get()
        if (currentState == AudioPlayerState.STOPPED || currentState == AudioPlayerState.IDLE) {
            return
        }
        
        releaseMediaPlayer()
        releaseAudioTrack()
        
        _state.set(AudioPlayerState.STOPPED)
    }

    private fun releaseMediaPlayer() {
        try {
            mediaPlayer?.let {
                if (it.isPlaying) {
                    it.stop()
                }
                it.release()
            }
        } catch (e: Exception) {
            Log.e(tag, "Error releasing MediaPlayer: ${e.message}")
        } finally {
            mediaPlayer = null
        }
    }

    private fun releaseAudioTrack() {
        try {
            audioTrack?.let {
                if (it.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    it.stop()
                    it.flush()
                }
                it.release()
            }
        } catch (e: Exception) {
            Log.e(tag, "Error releasing AudioTrack: ${e.message}")
        } finally {
            audioTrack = null
        }
    }

    private fun playPcmSafe(file: File) {
        val wavBytes = try {
            file.readBytes()
        } catch (e: Exception) {
            Log.e(tag, "Failed to read file for PCM playback: ${e.message}")
            _state.set(AudioPlayerState.ERROR)
            return
        }
        playPcm(wavBytes)
    }

    private fun playPcm(wavBytes: ByteArray) {
        if (wavBytes.size < 44) {
            _state.set(AudioPlayerState.ERROR)
            return
        }
        try {
            val sampleRate = ByteBuffer.wrap(wavBytes, 24, 4).order(ByteOrder.LITTLE_ENDIAN).int
            val channels = ByteBuffer.wrap(wavBytes, 22, 2).order(ByteOrder.LITTLE_ENDIAN).short.toInt()
            val bitsPerSample = ByteBuffer.wrap(wavBytes, 34, 2).order(ByteOrder.LITTLE_ENDIAN).short.toInt()

            var dataOffset = 44
            for (i in 36 until wavBytes.size - 4) {
                if (wavBytes[i] == 'd'.code.toByte() && wavBytes[i + 1] == 'a'.code.toByte() &&
                    wavBytes[i + 2] == 't'.code.toByte() && wavBytes[i + 3] == 'a'.code.toByte()) {
                    dataOffset = i + 8
                    break
                }
            }

            val pcmData = wavBytes.copyOfRange(dataOffset, wavBytes.size)
            val channelConfig = if (channels == 2) AudioFormat.CHANNEL_OUT_STEREO else AudioFormat.CHANNEL_OUT_MONO
            val encoding = if (bitsPerSample == 16) AudioFormat.ENCODING_PCM_16BIT else AudioFormat.ENCODING_PCM_8BIT

            val minBuf = AudioTrack.getMinBufferSize(sampleRate, channelConfig, encoding)
            val bufSize = maxOf(minBuf, pcmData.size)

            audioTrack = AudioTrack(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setChannelMask(channelConfig)
                    .setEncoding(encoding)
                    .build(),
                bufSize,
                AudioTrack.MODE_STATIC,
                AudioManager.AUDIO_SESSION_ID_GENERATE
            )

            audioTrack?.let { track ->
                track.write(pcmData, 0, pcmData.size)
                _state.set(AudioPlayerState.PLAYING)
                track.play()
            }
        } catch (e: Exception) {
            Log.e(tag, "AudioTrack playback failed: ${e.message}")
            _state.set(AudioPlayerState.ERROR)
            releaseAudioTrack()
        }
    }
}
