import os
import tempfile

import numpy as np
import pytest
from fastapi import Request
from fastapi.testclient import TestClient

from tools.metanoia_server.cache import TTSCacheManager


@pytest.fixture(autouse=True)
def temp_data_dirs(monkeypatch):
    with tempfile.TemporaryDirectory() as tmpdir:
        cache_dir = os.path.join(tmpdir, "cache")
        data_dir = os.path.join(tmpdir, "data")
        uploads_dir = os.path.join(tmpdir, "uploads")
        os.makedirs(cache_dir)
        os.makedirs(data_dir)
        os.makedirs(uploads_dir)

        monkeypatch.setattr("tools.metanoia_server.core.CACHE_DIR", cache_dir)
        monkeypatch.setattr("tools.metanoia_server.core.CACHE_DB", os.path.join(cache_dir, "index.db"))
        monkeypatch.setattr("tools.metanoia_server.core.VOICES_FILE", os.path.join(data_dir, "voices.json"))
        monkeypatch.setattr("tools.metanoia_server.core.UPLOADS_DIR", uploads_dir)
        yield


class MockEngine:
    sample_rate = 24000

    def generate(self, text, mode="speedy", voice="Vivian", instruct=None,
                 speed=1.0, ref_audio=None, ref_text=None, temperature=0.5,
                 cfg_scale=2.0):
        duration = int(self.sample_rate * max(0.5, len(text) * 0.05))
        wav = np.sin(2 * np.pi * 440 * np.arange(duration) / self.sample_rate)
        return wav, self.sample_rate

    def precompute_voice_prompt(self, name, audio_path, ref_text=None, mode="speedy"):
        pass


@pytest.fixture
def app(temp_data_dirs):
    from tools.metanoia_server.routes.generation import get_engine, get_cache
    from tools.metanoia_server.main import app as _app

    def mock_get_engine(request: Request):
        return MockEngine()

    def mock_get_cache(request: Request):
        return _app.state.cache

    _app.dependency_overrides[get_engine] = mock_get_engine
    _app.dependency_overrides[get_cache] = mock_get_cache

    return _app


@pytest.fixture
def client(app):
    with TestClient(app) as c:
        yield c


@pytest.fixture
def isolated_cache():
    with tempfile.TemporaryDirectory() as tmpdir:
        import tools.metanoia_server.core as core
        cache_dir = os.path.join(tmpdir, "cache")
        data_dir = os.path.join(tmpdir, "data")
        os.makedirs(cache_dir)
        os.makedirs(data_dir)

        orig_cache_dir = core.CACHE_DIR
        orig_cache_db = core.CACHE_DB
        core.CACHE_DIR = cache_dir
        core.CACHE_DB = os.path.join(cache_dir, "index.db")

        cache = TTSCacheManager()
        yield cache

        core.CACHE_DIR = orig_cache_dir
        core.CACHE_DB = orig_cache_db
