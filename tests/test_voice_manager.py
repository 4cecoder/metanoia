import os
import json

from tools.metanoia_server.voice_manager import load_voices, save_voices


class TestLoadVoices:
    def test_returns_dict(self):
        voices = load_voices()
        assert isinstance(voices, dict)

    def test_loads_from_file(self):
        from tools.metanoia_server.core import VOICES_FILE
        test_data = {"alice": {"audio": "data/alice.wav", "text": "hello", "mode": "speedy"}}
        os.makedirs(os.path.dirname(VOICES_FILE), exist_ok=True)
        with open(VOICES_FILE, "w") as f:
            json.dump(test_data, f)
        voices = load_voices()
        assert "alice" in voices


class TestSaveVoices:
    def test_saves_to_file(self):
        from tools.metanoia_server.core import VOICES_FILE
        test_data = {"bob": {"audio": "data/bob.wav", "text": "hi", "mode": "gold"}}
        os.makedirs(os.path.dirname(VOICES_FILE), exist_ok=True)
        save_voices(test_data)
        with open(VOICES_FILE) as f:
            loaded = json.load(f)
        assert loaded == test_data

    def test_roundtrip(self):
        original = load_voices()
        save_voices(original)
        reloaded = load_voices()
        assert original == reloaded
