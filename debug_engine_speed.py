import os
import sys
import time
import torch
import numpy as np
import soundfile as sf

# Add tools to path
sys.path.append(os.path.join(os.getcwd(), "tools"))

from torch_engine import TorchEngine

def test_speed():
    print("Initializing engine...")
    engine = TorchEngine()

    print("Loading models (speedy)...")
    engine.load_models("speedy")

    voice = "tommy"
    audio_path = "data/tommy.wav"
    ref_text = "Okay, I do believe I am live"

    print(f"Pre-caching voice: {voice}")
    engine.precompute_voice_prompt(voice, audio_path, ref_text, mode="speedy")

    text = "This is a fast test on the RTX 4090. Everything is pre-cached and ready to go."

    print(f"Starting generation 1 for: '{text}'")
    t0 = time.time()
    wav, sr = engine.generate(
        text=text,
        mode="speedy",
        voice=voice,
        speed=1.0,
        ref_audio=audio_path,
        ref_text=ref_text
    )
    t1 = time.time()
    print(f"Generation 1 complete in {t1-t0:.2f}s")

    print(f"Starting generation 2 for: '{text}'")
    t2 = time.time()
    wav, sr = engine.generate(
        text=text,
        mode="speedy",
        voice=voice,
        speed=1.0,
        ref_audio=audio_path,
        ref_text=ref_text
    )
    t3 = time.time()
    print(f"Generation 2 complete in {t3-t2:.2f}s")

    # Save output
    sf.write("standalone_test.wav", wav, sr)
    print("Saved to standalone_test.wav")

if __name__ == "__main__":
    test_speed()
