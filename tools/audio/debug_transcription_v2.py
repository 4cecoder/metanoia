from faster_whisper import WhisperModel
import os

model = WhisperModel("small", device="cpu", compute_type="int8")

for f in ["data/roumie.wav", "data/roumie2.wav"]:
    print(f"File: {f}")
    segments, info = model.transcribe(f, beam_size=5)
    text = " ".join([s.text for s in segments]).strip()
    print(f"Transcription: {text}")
    print("-" * 20)
