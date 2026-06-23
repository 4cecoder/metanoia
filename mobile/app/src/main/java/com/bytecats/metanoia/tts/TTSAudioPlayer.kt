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

class TTSAudioPlayer {
    private var mediaPlayer: MediaPlayer? = null
    private var audioTrack: AudioTrack? = null
    private val tag = "TTSAudioPlayer"

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
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.e(tag, "playAudio failed: ${e.message}")
            playPcm(file.readBytes())
        }
    }

    fun stop() {
        mediaPlayer?.let { it.stop(); it.release() }
        mediaPlayer = null
        audioTrack?.let { it.stop(); it.release() }
        audioTrack = null
    }

    private fun playPcm(wavBytes: ByteArray) {
        if (wavBytes.size < 44) return
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
                track.play()
            }
        } catch (e: Exception) {
            Log.e(tag, "AudioTrack playback failed: ${e.message}")
        }
    }
}
