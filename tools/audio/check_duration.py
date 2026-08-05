from pydub import AudioSegment
import os

audio = AudioSegment.from_wav("data/roumie.wav")
print(f"Duration: {len(audio) / 1000.0}s")
