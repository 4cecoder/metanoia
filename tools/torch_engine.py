import os
import torch
import numpy as np
import logging
from typing import Optional, List, Dict, Union, Any

# Configure logging
logger = logging.getLogger("metanoia-torch")

class TorchEngine:
    def __init__(self):
        self.models = {}
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.dtype = torch.float16 if self.device == "cuda" else torch.float32
        self.model_paths = {
            "speedy": "Qwen/Qwen3-TTS-12Hz-0.6B-Base",
            "gold": "Qwen/Qwen3-TTS-12Hz-0.6B-Base",
            "custom": "Qwen/Qwen3-TTS-12Hz-0.6B-Base" # Fallback to base
        }
        self.prompt_cache = {}

    def load_models(self, mode: Optional[str] = None):
        """Lazy load models based on requested mode using Transformers/Torch."""
        try:
            from qwen_tts import Qwen3TTSModel
            
            # Auto-detect flash attention availability
            attn_implementation = "eager"
            if self.device == "cuda":
                try:
                    import flash_attn
                    attn_implementation = "flash_attention_2"
                    logger.info("Flash Attention 2 detected and enabled.")
                except ImportError:
                    logger.info("Flash Attention not found, using default attention.")

            modes = [mode] if mode else ["speedy"]
            for key in modes:
                if key in self.models: continue
                model_id = self.model_paths.get(key)
                logger.info(f"Loading Torch model {key} on {self.device} (Attn: {attn_implementation})...")
                
                model = Qwen3TTSModel.from_pretrained(
                    model_id,
                    device_map=self.device,
                    torch_dtype=self.dtype,
                    attn_implementation=attn_implementation
                )
                self.models[key] = model
        except ImportError:
            logger.error("torch_engine: 'qwen_tts' package not found. Please install the Qwen3-TTS torch implementation.")
            raise RuntimeError("TorchEngine requires 'qwen_tts' package for NVIDIA/CUDA support.")

    def precompute_voice_prompt(self, name: str, audio_path: str, ref_text: Optional[str] = None, mode: str = "speedy"):
        """Pre-calculates reference audio for faster/higher quality cloning."""
        if not os.path.exists(audio_path):
            return

        logger.info(f"Pre-computing Torch prompt for {name}...")
        # Torch implementation would involve extracting latents from audio
        # self.prompt_cache[name] = ...
        pass

    @property
    def sample_rate(self):
        return 24000

    def generate(
        self, 
        text: str, 
        mode: str = "speedy",
        voice: str = "Vivian", 
        instruct: Optional[str] = None, 
        speed: float = 1.0,
        ref_audio: Optional[str] = None,
        ref_text: Optional[str] = None,
        temperature: float = 0.5,
        cfg_scale: float = 2.0
    ):
        model = self.models.get(mode) or self.models.get("speedy")
        if not model:
            self.load_models(mode)
            model = self.models.get(mode)

        logger.info(f"Generating Torch audio for text ({len(text)} chars)...")
        
        # Prepare generation arguments
        # Note: API names may vary slightly based on the final qwen_tts package release
        gen_kwargs = {
            "text": text,
            "ref_audio": ref_audio,
            "ref_text": ref_text,
            "speed": speed,
            "temperature": temperature,
            "cfg_scale": cfg_scale,
            "language": "en" # Default to English for now
        }
        
        if instruct:
            gen_kwargs["instruct"] = instruct

        try:
            # Generate using the Torch model
            with torch.no_grad():
                audio_values = model.generate(**gen_kwargs)
            
            # Convert to numpy array and ensure it's on CPU
            if isinstance(audio_values, list) or isinstance(audio_values, tuple):
                wav = audio_values[0]
            else:
                wav = audio_values
                
            if hasattr(wav, "cpu"):
                wav = wav.cpu().numpy()
            
            # Squeeze to 1D if necessary
            wav = np.squeeze(wav)
            
            # Trim silence for punchy playback
            wav = self.trim_silence(wav)
            
            return wav, self.sample_rate
            
        except Exception as e:
            logger.error(f"Torch generation failed: {e}")
            raise

    def trim_silence(self, wav: np.ndarray, threshold: float = 0.005) -> np.ndarray:
        # Same logic as MLXEngine
        mask = np.abs(wav) > threshold
        if not np.any(mask): return wav
        start_idx = max(0, np.argmax(mask) - 6000)
        end_idx = min(len(wav), len(wav) - np.argmax(mask[::-1]) + 6000)
        return wav[start_idx:end_idx]
