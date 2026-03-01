from faster_whisper import WhisperModel
import soundfile as sf

model = WhisperModel("small", device="cpu", compute_type="int8")
segments, info = model.transcribe("data/roumie2.wav", beam_size=5)

print(f"Full Transcription for roumie2.wav:")
for segment in segments:
    print(f"[{segment.start:.2f}s -> {segment.end:.2f}s] {segment.text}")
