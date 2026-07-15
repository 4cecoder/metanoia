import os
from mlx_audio.tts import load as load_tts_model
import inspect

def inspect_model_methods():
    model_path = "models/Qwen3-TTS-12Hz-0.6B-Base-bf16"
    if not os.path.exists(model_path):
        print("Model not found")
        return
        
    print(f"Loading {model_path}...")
    model = load_tts_model(model_path)
    
    print("\nModel Methods:")
    for name, member in inspect.getmembers(model):
        if not name.startswith('_'):
            print(f"  {name}")

if __name__ == "__main__":
    inspect_model_methods()
