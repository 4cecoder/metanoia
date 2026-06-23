package com.bytecats.metanoia.models

data class RemoteVoice(
    val key: String,
    val displayName: String,
    val exists: Boolean,
    val type: String,
    val text: String? = null
)

data class TtsRequest(
    val text: String,
    val voice: String,
    val speed: Float = 1.0f,
    val mode: String = "speedy"
)
