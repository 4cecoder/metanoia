import os
from typing import Optional

from .core import logger
from .system import SystemDetector


class EngineContainer:
    def __init__(self):
        self.mlx_engine = None
        self.torch_engine = None
        self.whisper_model = None

    def get_active(self) -> Optional[object]:
        return self.mlx_engine or self.torch_engine


def _load_mlx_engine(container: EngineContainer, voice_configs: dict) -> Optional[object]:
    try:
        from mlx_engine import MLXEngine  # type: ignore[import-untyped]
        engine = MLXEngine()
        # Keep the fast 0.6B Base model resident.  Gold/custom models are
        # still lazy-loaded by MLXEngine when a request actually needs them;
        # loading all three at startup needlessly consumes unified memory and
        # competes with the model doing the first synthesis.
        engine.load_models("speedy")
        container.mlx_engine = engine
        logger.info("MLXEngine loaded on Apple Silicon")
        return engine
    except ImportError:
        logger.warning("mlx_engine module not available")
    except Exception as e:
        logger.error(f"MLXEngine failed to load: {e}")
    return None


def _load_torch_engine(container: EngineContainer, voice_configs: dict) -> Optional[object]:
    try:
        import torch
        from torch_engine import TorchEngine  # type: ignore[import-untyped]
        engine = TorchEngine()
        engine.load_models()
        container.torch_engine = engine
        logger.info(f"TorchEngine initialized (CUDA: {torch.cuda.is_available()})")
        return engine
    except ImportError:
        logger.warning("torch_engine module not available")
    except Exception as e:
        logger.error(f"TorchEngine failed to load: {e}")
    return None


def _precompute_prompts(engine: object, voice_configs: dict):
    for name, cfg in voice_configs.items():
        # Prompt precomputation is deliberately limited to the resident fast
        # model.  A gold/custom voice will pay its one-time preparation cost on
        # first use, instead of slowing every startup and evicting speedy
        # weights from Apple's unified memory.
        if cfg.get("mode", "speedy") != "speedy":
            continue
        audio_path = cfg.get("audio")
        if audio_path and os.path.exists(audio_path):
            try:
                engine.precompute_voice_prompt(
                    name=name,
                    audio_path=audio_path,
                    ref_text=cfg.get("text", ""),
                    mode=cfg.get("mode", "speedy"),
                )
            except Exception as e:
                logger.warning(f"Could not pre-compute prompt for {name}: {e}")


def _load_whisper(container: EngineContainer):
    try:
        from faster_whisper import WhisperModel
        cuda_available = False
        try:
            import torch
            cuda_available = torch.cuda.is_available()
        except ImportError:
            pass
        device = "cuda" if cuda_available else "cpu"
        container.whisper_model = WhisperModel("small", device=device, compute_type="int8")
        logger.info(f"Whisper loaded on {device}")
    except Exception as e:
        logger.warning(f"Whisper model failed to load: {e}")


def load_engines(container: EngineContainer, voice_configs: dict):
    use_mlx = SystemDetector.preferred_backend() == "mlx"

    if use_mlx:
        engine = _load_mlx_engine(container, voice_configs)
        if not engine:
            logger.info("MLX not available, falling back to Torch")
            engine = _load_torch_engine(container, voice_configs)
    else:
        engine = _load_torch_engine(container, voice_configs)

    if engine:
        _precompute_prompts(engine, voice_configs)
    else:
        logger.error("No TTS engine could be loaded")

    _load_whisper(container)
