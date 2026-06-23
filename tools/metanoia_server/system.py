import platform
import importlib.util
from typing import Optional

from .core import logger


class SystemDetector:
    _mlx_cache: Optional[bool] = None

    @staticmethod
    def is_macos() -> bool:
        return platform.system() == "Darwin"

    @staticmethod
    def is_apple_silicon() -> bool:
        return platform.system() == "Darwin" and platform.machine() in ("arm64", "aarch64")

    @staticmethod
    def mlx_available() -> bool:
        if SystemDetector._mlx_cache is None:
            SystemDetector._mlx_cache = importlib.util.find_spec("mlx") is not None
        return SystemDetector._mlx_cache

    @staticmethod
    def preferred_backend() -> str:
        if SystemDetector.is_macos() and SystemDetector.is_apple_silicon() and SystemDetector.mlx_available():
            return "mlx"
        return "torch"

    @staticmethod
    def device_name() -> str:
        if SystemDetector.is_macos() and SystemDetector.is_apple_silicon():
            return "Metal (Apple GPU)"
        if SystemDetector.mlx_available():
            return "MLX (Apple Silicon)"
        try:
            import torch
            if torch.cuda.is_available():
                return torch.cuda.get_device_name(0)
            return "CPU"
        except ImportError:
            return "CPU"

    @staticmethod
    def summary() -> dict:
        return {
            "platform": platform.system(),
            "machine": platform.machine(),
            "is_macos": SystemDetector.is_macos(),
            "is_apple_silicon": SystemDetector.is_apple_silicon(),
            "mlx_available": SystemDetector.mlx_available(),
            "preferred_backend": SystemDetector.preferred_backend(),
            "device_name": SystemDetector.device_name(),
        }
