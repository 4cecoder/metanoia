import os
import sys
import torch

# Add tools to path
sys.path.append(os.path.join(os.getcwd(), "tools"))

from qwen_tts import Qwen3TTSModel

def inspect():
    model_id = "Qwen/Qwen3-TTS-12Hz-0.6B-Base"
    print(f"Loading model {model_id}...")
    model = Qwen3TTSModel.from_pretrained(model_id, device_map="cpu", torch_dtype=torch.float32)

    print("
Model methods:")
    for m in sorted(dir(model)):
        if not m.startswith("_"):
            print(f"  {m}")

    if hasattr(model, "model"):
        print("
Internal model (model.model) methods:")
        for m in sorted(dir(model.model)):
            if not m.startswith("_"):
                print(f"  {m}")

if __name__ == "__main__":
    inspect()
