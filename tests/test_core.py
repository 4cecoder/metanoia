import os
import pytest
from tools.metanoia_server.core import TTSRequest, VoiceUpsertRequest, ensure_dirs


class TestTTSRequest:
    def test_default_values(self):
        req = TTSRequest(text="hello")
        assert req.text == "hello"
        assert req.voice == "tommy"
        assert req.speed == 1.0
        assert req.mode == "base"
        assert req.force_refresh is False
        assert req.temperature == 0.5
        assert req.cfg_scale == 2.0
        assert req.style == "Natural"
        assert req.emotion is None

    def test_custom_values(self):
        req = TTSRequest(text="test", voice="lennox", speed=1.5, mode="speedy")
        assert req.voice == "lennox"
        assert req.speed == 1.5
        assert req.mode == "speedy"

    def test_invalid_speed_type(self):
        with pytest.raises(ValueError):
            TTSRequest(text="test", speed="fast")


class TestVoiceUpsertRequest:
    def test_defaults(self):
        req = VoiceUpsertRequest(name="test_voice")
        assert req.name == "test_voice"
        assert req.text is None
        assert req.mode == "speedy"
        assert req.audio is None

    def test_custom(self):
        req = VoiceUpsertRequest(name="v", text="hello", mode="gold", audio="data/v.wav")
        assert req.text == "hello"
        assert req.mode == "gold"
        assert req.audio == "data/v.wav"


class TestEnsureDirs:
    def test_creates_directories(self, monkeypatch):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            monkeypatch.setattr("tools.metanoia_server.core.CACHE_DIR", os.path.join(tmp, "cache"))
            monkeypatch.setattr("tools.metanoia_server.core.UPLOADS_DIR", os.path.join(tmp, "uploads"))
            monkeypatch.setattr("tools.metanoia_server.core.VOICES_FILE", os.path.join(tmp, "data", "voices.json"))
            os.makedirs(os.path.join(tmp, "data"), exist_ok=True)
            ensure_dirs()
            assert os.path.isdir(os.path.join(tmp, "cache"))
            assert os.path.isdir(os.path.join(tmp, "uploads"))
