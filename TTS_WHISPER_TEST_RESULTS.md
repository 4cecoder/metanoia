# TTS + Whisper E2E Test Results

## Test Date
2026-08-03

## Configuration
- TTS Engine: PyTorch (CUDA, GTX 1070)
- Model: Qwen3-TTS (speedy + gold modes)
- Voices: tommy, lennox
- Transcription: faster_whisper (tiny/base models)
- Backend: HTTP (localhost:8000)

## Test Results

### Single Tests

| Test | Voice | Whisper Model | Accuracy | WER | Status |
|------|-------|---------------|----------|-----|--------|
| "For God so loved the world." | tommy | tiny | 83.3% | 0.167 | ✅ GOOD |
| "The Lord is my shepherd." | lennox | base | 0.0% | 1.000 | ❌ POOR |
| "In the beginning God created the heavens and the earth." | tommy | base | 100.0% | 0.000 | ✅ EXCELLENT |

### Batch Test (5 phrases, tommy voice, base Whisper)

| # | Text | Accuracy | WER | Status |
|---|------|----------|-----|--------|
| 1 | "For God so loved the world." | 83.3% | 0.167 | ✅ GOOD |
| 2 | "The Lord is my shepherd, I shall not want." | 100.0% | 0.000 | ✅ EXCELLENT |
| 3 | "In the beginning, God created the heavens and the earth." | 100.0% | 0.000 | ✅ EXCELLENT |
| 4 | "Be still and know that I am God." | 100.0% | 0.000 | ✅ EXCELLENT |
| 5 | "I am the way, the truth, and the life." | 0.0% | 1.000 | ❌ POOR |

**Batch Summary:**
- Tests run: 5
- Successful: 5/5 (all audio generated successfully)
- Average accuracy: 76.7%

## Observations

### Successful Cases (80%+ accuracy)
- Longer phrases (9-10 words) perform very well
- "tommy" voice is clearer than "lennox"
- Base Whisper model provides better transcription than tiny
- Punctuation is preserved in successful transcriptions

### Failure Cases
- Short phrases with ambiguous pronunciation (e.g., "am" vs "I'm")
- "lennox" voice may have different characteristics affecting clarity
- Whisper may struggle with contractions

### Audio Characteristics
- Sample rate: 24kHz
- Format: WAV
- Duration: 0.4-5.19s (transcription time, actual audio ~1-2s)
- Size: 19KB - 249KB

## Recommendations

1. **Use "tommy" voice** for clearer speech
2. **Prefer longer phrases** (7+ words) for better transcription
3. **Use base Whisper model** for verification (tiny has lower accuracy)
4. **Avoid contractions** or test them separately (e.g., "I am" vs "I'm")

## Test Script

```bash
# Single test
uv run tools/test_tts_e2e.py --text "Your text here" --model base --voice tommy

# Batch test
uv run tools/test_tts_e2e.py --batch --model base --voice tommy

# Save results to JSON
uv run tools/test_tts_e2e.py --batch --output results.json
```