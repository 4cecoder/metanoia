import platform
import importlib.util

import pytest

from tools.metanoia_server.system import SystemDetector


class TestSystemDetector:
    def test_is_macos(self):
        assert SystemDetector.is_macos() == (platform.system() == "Darwin")

    def test_is_apple_silicon(self):
        expected = platform.system() == "Darwin" and platform.machine() in ("arm64", "aarch64")
        assert SystemDetector.is_apple_silicon() == expected

    def test_mlx_available(self):
        expected = importlib.util.find_spec("mlx") is not None
        assert SystemDetector.mlx_available() == expected

    def test_preferred_backend(self):
        is_macos_silicon = platform.system() == "Darwin" and platform.machine() in ("arm64", "aarch64")
        mlx_found = importlib.util.find_spec("mlx") is not None
        if is_macos_silicon and mlx_found:
            assert SystemDetector.preferred_backend() == "mlx"
        else:
            assert SystemDetector.preferred_backend() == "torch"

    def test_device_name_returns_string(self):
        name = SystemDetector.device_name()
        assert isinstance(name, str)
        assert len(name) > 0

    def test_summary_returns_dict(self):
        summary = SystemDetector.summary()
        assert isinstance(summary, dict)
        assert "platform" in summary
        assert "machine" in summary
        assert "is_macos" in summary
        assert "is_apple_silicon" in summary
        assert "mlx_available" in summary
        assert "preferred_backend" in summary
        assert "device_name" in summary
        assert summary["is_macos"] == (platform.system() == "Darwin")

    def test_mlx_cache_persists(self):
        SystemDetector._mlx_cache = None
        result1 = SystemDetector.mlx_available()
        assert SystemDetector._mlx_cache is not None
        result2 = SystemDetector.mlx_available()
        assert result1 == result2
