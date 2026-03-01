from faster_whisper import WhisperModel
import os

# Use the large-v3 model for maximum accuracy on reference text
model = WhisperModel("large-v3", device="cpu", compute_type="int8")

files = ["data/mari_ref.wav", "data/shamoun_ref.wav"]

for f in files:
    print(f"Transcribing: {f}")
    segments, info = model.transcribe(f, beam_size=5)
    text = " ".join([s.text for s in segments]).strip()
    print(f"Result: {text}")
    print("-" * 20)
