import soundfile as sf
import numpy as np
from faster_whisper import WhisperModel
import os

# 1. Trim to 15 seconds
input_path = "data/roumie2.wav"
output_path = "data/roumie_15s.wav"

data, samplerate = sf.read(input_path)
max_samples = 15 * samplerate
trimmed_data = data[:max_samples]

sf.write(output_path, trimmed_data, samplerate)
print(f"Trimmed {input_path} to {output_path} (Duration: {len(trimmed_data)/samplerate:.2f}s)")

# 2. Transcribe the trimmed clip
model = WhisperModel("small", device="cpu", compute_type="int8")
segments, info = model.transcribe(output_path, beam_size=5)
text = " ".join([s.text for s in segments]).strip()
print(f"New Transcription: {text}")
