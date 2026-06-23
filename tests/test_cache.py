import os

import pytest

from tools.metanoia_server.cache import TTSCacheManager


class TestTTSCacheManager:
    def test_init_creates_db_and_dirs(self, isolated_cache):
        assert isolated_cache.conn is not None

    def test_add_and_get(self, isolated_cache):
        cache = isolated_cache
        wav_path = os.path.join(cache.conn.execute("PRAGMA database_list").fetchone()[2].replace("/index.db", ""), "test.wav")
        os.makedirs(os.path.dirname(wav_path), exist_ok=True)
        with open(wav_path, "wb") as f:
            f.write(b"\x00" * 100)

        cache.add("key1", wav_path, "hello", "tommy", "abc123")
        result = cache.get("key1")
        assert result == wav_path

    def test_get_missing(self, isolated_cache):
        assert isolated_cache.get("nonexistent") is None

    def test_get_stale_file_removes_entry(self, isolated_cache):
        cache = isolated_cache
        db_dir = os.path.dirname(cache.conn.execute("PRAGMA database_list").fetchone()[2].replace("/index.db", ""))
        wav_path = os.path.join(db_dir, "stale.wav")
        with open(wav_path, "wb") as f:
            f.write(b"\x00" * 100)

        cache.add("stale", wav_path, "text", "voice", "hash")
        os.remove(wav_path)
        assert cache.get("stale") is None

        cursor = cache.conn.execute("SELECT COUNT(*) FROM tts_cache WHERE key = 'stale'")
        assert cursor.fetchone()[0] == 0

    def test_multiple_entries(self, isolated_cache):
        cache = isolated_cache
        db_dir = os.path.dirname(cache.conn.execute("PRAGMA database_list").fetchone()[2].replace("/index.db", ""))
        paths = []
        for i in range(5):
            path = os.path.join(db_dir, f"test_{i}.wav")
            with open(path, "wb") as f:
                f.write(b"\x00" * (100 + i))
            cache.add(f"key{i}", path, f"text{i}", "tommy", f"hash{i}")
            paths.append(path)

        for i in range(5):
            assert cache.get(f"key{i}") == paths[i]
