from faster_whisper import WhisperModel
import os
import sys

def transcribe(audio_path):
    if not os.path.exists(audio_path):
        print(f"Error: {audio_path} not found.")
        return

    print(f"Transcribing {audio_path} using Faster Whisper...")
    
    model_size = "small"
    model = WhisperModel(model_size, device="cpu", compute_type="int8")

    segments, info = model.transcribe(audio_path, beam_size=5, vad_filter=True)

    print(f"Detected language '{info.language}' with probability {info.language_probability:.2f}")

    full_text = ""
    for segment in segments:
        full_text += segment.text + " "
    
    full_text = full_text.strip()
    print("\nTranscription Result:")
    print("-" * 20)
    print(full_text)
    print("-" * 20)
    
    return full_text

if __name__ == "__main__":
    path = "data/reference_2.wav"
    if len(sys.argv) > 1:
        path = sys.argv[1]
    transcribe(path)
