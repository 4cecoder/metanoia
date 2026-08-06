# Gateway Migration Guide

## Overview

This guide describes the migration from gateway-based AI services to native Qwen3-TTS forward pass implementation in Kotlin. The gateway system has been deprecated and will be removed in version 3.0.

## Deprecation Notice

**All gateway connection settings and code are deprecated as of version 2.x and will be removed in version 3.0.**

Please migrate to native neural TTS implementation as soon as possible.

## What's Being Deprecated

### Gateway Client
- `GatewayClient.kt` - Unified HTTP client for AI VM Gateway
- `TTSManager.kt` - Gateway-based TTS management
- `STTManager.kt` - Gateway-based speech-to-text
- All gateway connection settings in `SettingsManager.kt`

### Gateway Settings
- `gatewayIp` - Gateway IP address setting
- `gatewayPort` - Gateway port setting  
- `gatewayUrl` - Gateway URL setting
- `useGatewayBible` - Bible API gateway setting
- `useExperimentalTTS` - Gateway TTS toggle

### Gateway UI
- `GatewaySettingsPage.kt` - Gateway connection configuration (now shows deprecation notice)
- Gateway connection tests and status indicators

## Native Replacement Architecture

### Qwen3-TTS Forward Pass
The native implementation provides:
- **Complete neural TTS**: Full forward pass of Qwen3-TTS transformer network
- **Local processing**: No network dependency, fully offline
- **GGUF model support**: Standard model format for easy voice management
- **High quality**: 24kHz audio output with neural synthesis
- **Voice cloning**: Support for voice profiles via GGUF models

### Core Components

#### 1. Qwen3TTSEngine
```kotlin
// Native neural TTS engine
val engine = Qwen3TTSEngine(
    modelPath = "/path/to/qwen_tts_2b.gguf",
    codecPath = "/path/to/codec.gguf"
)
engine.init()
val audio = engine.synthesize("Hello, world!", speed = 1.0f)
```

**Features:**
- RMS normalization (output = x * w / sqrt(mean(x^2) + eps))
- SwiGLU feed-forward (silu(gate) * up → down)
- GQA support (num_attention_heads vs num_key_value_heads)
- RoPE positional encoding support
- 12Hz audio generation rate (12 tokens per second)

#### 2. GGUFReader
```kotlin
// Read GGUF model files
val reader = GGUFReader(File("qwen_tts_2b.gguf"))
val tensor = reader.getTensor("model.embed_tokens.weight")
```

**Features:**
- GGUF format parsing
- Tensor weight extraction
- Metadata reading (model config, hyperparameters)
- Memory-mapped file access for efficiency

#### 3. BPETokenizer
```kotlin
// Byte-pair encoding for text preprocessing
val tokenizer = BPETokenizer(merges, vocab)
val tokens = tokenizer.encode("Hello, world!")
```

**Features:**
- Byte-pair encoding tokenization
- Text preprocessing for neural models
- Vocabulary management
- Efficient encoding/decoding

## Migration Examples

### Example 1: Basic Text-to-Speech

**Before (Gateway):**
```kotlin
val ttsManager = TTSManager(context)
val audioFile = ttsManager.generateSpeech("Hello, world!", "lennox")
```

**After (Native):**
```kotlin
val engine = Qwen3TTSEngine(
    modelPath = "/data/data/com.bytecats.metanoia/files/qwen_tts_2b.gguf",
    codecPath = "/data/data/com.bytecats.metanoia/files/codec.gguf"
)
engine.init()
val audioData = engine.synthesize("Hello, world!", speed = 1.0f)
// Save to file
val audioFile = File(context.cacheDir, "output.wav")
audioFile.writeBytes(audioData)
```

### Example 2: Voice Cloning

**Before (Gateway):**
```kotlin
val ttsManager = TTSManager(context)
val audioFile = ttsManager.cloneDynamic(
    "Hello, world!",
    referenceAudioBytes,
    "Reference text"
)
```

**After (Native):**
```kotlin
val engine = Qwen3TTSEngine(
    modelPath = "/path/to/voice_clone_model.gguf",
    codecPath = "/path/to/codec.gguf"
)
engine.init()
// Load voice profile from GGUF
val audioData = engine.synthesize(
    "Hello, world!",
    speed = 1.0f,
    // Voice profile is embedded in the model
)
```

### Example 3: Voice Management

**Before (Gateway):**
```kotlin
val ttsManager = TTSManager(context)
val voices = ttsManager.fetchFullStatus()
ttsManager.deleteVoice("old_voice")
ttsManager.upsertVoice("new_voice", "Reference text")
```

**After (Native):**
```kotlin
// Voice management via GGUF files
val voiceFile = File(context.filesDir, "voices/custom_voice.gguf")
// Copy/delete/manage GGUF files directly
File(voicePath).delete()
File(sourceVoicePath).copyTo(File(destVoicePath))
```

### Example 4: Speech-to-Text

**Before (Gateway):**
```kotlin
val sttManager = STTManager(context)
val transcription = sttManager.transcribe(audioBytes)
```

**After (Android Native):**
```kotlin
// Use Android SpeechRecognizer as temporary solution
val speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)
val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
    putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.US)
}
// Native Whisper implementation coming soon
```

### Example 5: Bible API

**Before (Gateway):**
```kotlin
val settings = SettingsManager(context)
settings.useGatewayBible = true
// BibleManager routes through gateway
```

**After (Direct Scraping):**
```kotlin
val settings = SettingsManager(context)
settings.useGatewayBible = false // Already false by default
// BibleManager uses BibleGatewayScraper directly
val bibleManager = BibleManager(context)
val chapter = bibleManager.getChapter("John", 1, "NKJV")
```

## Configuration Migration

### Settings Changes

**Deprecated Settings (remove from use):**
- `settings.gatewayIp`
- `settings.gatewayPort` 
- `settings.gatewayUrl`
- `settings.useGatewayBible`
- `settings.useExperimentalTTS` (toggles between gateway/native)

**New Native Configuration:**
```kotlin
// No new settings required for basic usage
// Model paths are handled by VoiceLab and default locations
// Advanced configuration via GGUF metadata
```

### UI Migration

**Gateway Settings Page:**
- Now shows deprecation notice
- All controls disabled (grayed out)
- Redirects users to Audio Settings for native configuration

**Audio Settings Page:**
- Enhanced to show native TTS status
- GGUF model configuration interface
- Removed gateway dependency references

## Benefits of Native Implementation

### Performance
- **No network latency**: All processing happens locally
- **Lower power consumption**: No constant network polling
- **Faster response times**: No HTTP round trips

### Reliability  
- **Offline functionality**: Works without internet connection
- **No gateway dependencies**: Self-contained application
- **Predictable performance**: No network variability

### Privacy
- **Local processing**: Audio never leaves device
- **No data transmission**: Complete privacy
- **User control**: Full control over model files

### Maintenance
- **Simplified architecture**: No gateway infrastructure needed
- **Easier testing**: Self-contained tests without network
- **Better debugging**: Full control over processing pipeline

## Timeline

### Version 2.x (Current)
- Gateway marked as deprecated
- Deprecation warnings in code and UI
- Native implementation fully functional
- Migration guide provided

### Version 2.x (Next release)
- Gateway warnings more prominent
- Default to native implementation
- Gateway settings hidden from new users
- Migration assistance tools

### Version 3.0 (Future)
- Gateway code completely removed
- All gateway settings removed
- Clean native-only architecture
- No backward compatibility

## Testing Migration

### Unit Tests
```kotlin
// Test native engine
class Qwen3TTSEngineTest {
    @Test
    fun testSynthesis() {
        val engine = Qwen3TTSEngine("test.gguf", "codec.gguf")
        engine.init()
        val audio = engine.synthesize("Test", speed = 1.0f)
        assertNotNull(audio)
        assertTrue(audio.size > 0)
    }
}
```

### Integration Tests
```kotlin
// Test full pipeline
class TTSPipelineTest {
    @Test
    fun testEndToEnd() {
        val audio = TTSPipeline.generate("Hello")
        val transcription = STTPipeline.transcribe(audio)
        assertTrue(transcription.contains("hello", ignoreCase = true))
    }
}
```

## Getting Help

### Documentation
- Native TTS architecture: See `Qwen3TTSEngine.kt`
- GGUF format: See `GGUFReader.kt`
- Tokenization: See `BPETokenizer.kt`
- Migration examples: See VoiceLab implementation

### Support Channels
- GitHub Issues: Report migration issues
- Documentation: Read inline code documentation
- Examples: Check VoiceLabScreen.kt for usage patterns

## Conclusion

The migration from gateway-based services to native Qwen3-TTS forward pass provides significant benefits in performance, reliability, and privacy. The native implementation is production-ready and provides all necessary functionality without external dependencies.

Start your migration today and enjoy the benefits of offline neural TTS!