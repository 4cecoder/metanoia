package com.bytecats.metanoia.tts

// Represents a voice profile on the gateway.
// Mapped from the gateway's voice listing endpoints.
data class RemoteVoice(
    val key: String,
    val displayName: String,
    val exists: Boolean,
    val type: String = "cloned"
)
