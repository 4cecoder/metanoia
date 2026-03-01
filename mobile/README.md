# Metanoia Mobile TTS (Pixel 9 Pro Offline)

This is a Kotlin port of the Metanoia TTS server, designed to run **Qwen3-TTS-0.6B** and **Whisper** locally on Android using **ONNX Runtime (ORT)** and **Tensor G4 NNAPI**.

## How to Port the Models
The 0.6B PyTorch model cannot run directly in Kotlin. You must convert it to ONNX:

### 1. Convert Qwen3-TTS to ONNX
```bash
python -m onnxruntime.tools.convert_onnx_models_to_ort 
  --model_path qwen3_tts.onnx 
  --output_dir app/src/main/assets/models/
```
*Note: Ensure you use INT8 quantization to keep the model under 700MB for mobile RAM.*

### 2. Convert Whisper to TFLite/ONNX
For the transcribe feature, use the `whisper.cpp` optimized Android models or OpenAI's official TFLite conversion.

## Android Dependencies
Add these to `build.gradle.kts`:
```kotlin
dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:latest")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.6.2")
}
```

## Hardware Optimization
On the Pixel 9 Pro, the **Tensor G4** chip supports `NNAPI`. When initializing the ONNX Session in `TTSManager.kt`, ensure you add the `NNAPI` execution provider for 10x faster generation.
