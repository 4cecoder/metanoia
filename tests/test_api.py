import os
import json

import pytest


class TestSystemInfo:
    def test_system_info_returns_expected_fields(self, client):
        resp = client.get("/system_info")
        assert resp.status_code == 200
        data = resp.json()
        for key in ("platform", "machine", "is_macos", "is_apple_silicon",
                     "mlx_available", "preferred_backend", "device_name"):
            assert key in data


class TestVoiceStatus:
    def test_voice_status_returns_voices(self, client):
        resp = client.get("/voice_status")
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, dict)

    def test_voice_status_with_custom_voice(self, client, monkeypatch):
        from tools.metanoia_server import core
        test_data = {"custom1": {"audio": None, "text": None, "mode": "custom"}}
        os.makedirs(os.path.dirname(core.VOICES_FILE), exist_ok=True)
        with open(core.VOICES_FILE, "w") as f:
            json.dump(test_data, f)

        resp = client.get("/voice_status")
        data = resp.json()
        assert "custom1" in data
        assert data["custom1"]["type"] == "premium"


class TestUpsertVoice:
    def test_create_voice(self, client):
        resp = client.post("/voices", json={"name": "test_voice"})
        assert resp.status_code == 200
        assert resp.json()["voice"] == "test_voice"

    def test_create_voice_normalizes_name(self, client):
        resp = client.post("/voices", json={"name": "My Voice"})
        assert resp.status_code == 200
        assert resp.json()["voice"] == "my_voice"

    def test_delete_voice(self, client):
        client.post("/voices", json={"name": "delete_me"})
        resp = client.delete("/voices/delete_me")
        assert resp.status_code == 200

    def test_delete_nonexistent_voice(self, client):
        resp = client.delete("/voices/nonexistent")
        assert resp.status_code == 404


class TestGenerate:
    def test_generate_basic(self, client):
        resp = client.post("/generate", json={"text": "Hello world"})
        assert resp.status_code == 200
        assert resp.headers["content-type"] == "audio/wav"
        assert len(resp.content) > 44

    def test_generate_with_voice(self, client):
        resp = client.post("/generate", json={
            "text": "Test with voice",
            "voice": "lennox",
            "speed": 1.0,
            "mode": "speedy",
        })
        assert resp.status_code == 200

    def test_generate_force_refresh(self, client):
        resp = client.post("/generate", json={
            "text": "Force test",
            "force_refresh": True,
        })
        assert resp.status_code == 200

    def test_generate_accepts_metadata_params(self, client):
        resp = client.post("/generate", json={
            "text": "Test",
            "voice": "tommy",
            "speed": 1.0,
            "mode": "speedy",
            "temperature": 0.5,
            "cfg_scale": 2.0,
            "force_refresh": False,
        })
        assert resp.status_code == 200
