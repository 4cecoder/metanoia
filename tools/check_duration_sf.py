import soundfile as sf
import os

info = sf.info("data/roumie.wav")
print(f"File: data/roumie.wav")
print(f"Duration: {info.duration}s")
print(f"Sample rate: {info.samplerate}")
print(f"Channels: {info.channels}")

info2 = sf.info("data/roumie2.wav")
print(f"File: data/roumie2.wav")
print(f"Duration: {info2.duration}s")
