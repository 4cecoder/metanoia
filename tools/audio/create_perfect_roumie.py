import soundfile as sf
import numpy as np
from faster_whisper import WhisperModel
import os

# 1. Create a 15-second clip (0-15s) from roumie_combined.wav
input_path = "data/roumie_combined.wav"
output_path = "data/roumie_perfect_15s.wav"

data, samplerate = sf.read(input_path)
# Ensure we have enough data
max_samples = min(15 * samplerate, len(data))
trimmed_data = data[:max_samples]

sf.write(output_path, trimmed_data, samplerate)
print(f"Created {output_path} (Duration: {len(trimmed_data)/samplerate:.2f}s)")

# 2. Transcribe exactly to ensure ref_text matches
model = WhisperModel("small", device="cpu", compute_type="int8")
segments, info = model.transcribe(output_path, beam_size=5)
text = " ".join([s.text for s in segments]).strip()
print(f"Exact Transcription for prompt: {text}")
