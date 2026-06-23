import os
import json
from typing import Dict, Any
from . import core

def load_voices() -> Dict[str, Any]:
    if not os.path.exists(core.VOICES_FILE):
        os.makedirs("data", exist_ok=True)
        initial_voices = {
            "tommy": {"audio": "data/tommy.wav", "text": "Okay, I do believe I am live", "mode": "speedy"},
            "lennox": {"audio": "data/lennox_ref.wav", "text": "We need to be worried, first of all, about what the AI that's currently working...", "mode": "speedy"},
        }
        with open(core.VOICES_FILE, "w") as f:
            json.dump(initial_voices, f, indent=2)
        return initial_voices

    with open(core.VOICES_FILE, "r") as f:
        return json.load(f)


def save_voices(voices: Dict[str, Any]):
    os.makedirs(os.path.dirname(core.VOICES_FILE), exist_ok=True)
    with open(core.VOICES_FILE, "w") as f:
        json.dump(voices, f, indent=2)
