from faster_whisper import WhisperModel
import os

model = WhisperModel("small", device="cpu", compute_type="int8")
segments, info = model.transcribe("data/roumie_combined.wav", beam_size=5)
text = " ".join([s.text for s in segments]).strip()
print(f"Transcription: {text}")
