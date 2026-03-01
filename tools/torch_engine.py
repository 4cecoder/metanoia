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
            "custom": "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice"
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
        # Ensure the requested mode is loaded
        if mode not in self.models:
            if mode in self.model_paths:
                self.load_models(mode)
            else:
                # Fallback to speedy if mode is unknown
                if "speedy" not in self.models:
                    self.load_models("speedy")
                mode = "speedy"
        
        model = self.models[mode]
        logger.info(f"Generating Torch audio using mode: {mode} (Model: {self.model_paths.get(mode)})")

        # Safety: Truncate text if it's exceptionally long to avoid CUDA asserts
        # Qwen3-TTS usually handles up to 512 tokens, roughly 400-500 chars
        if len(text) > 400:
            logger.warning(f"Text too long ({len(text)} chars). Truncating to 400 to avoid CUDA assert.")
            text = text[:400]

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
                # Check if we should use custom voice (predefined speakers)
                if mode == "custom" and hasattr(model, "generate_custom_voice"):
                    logger.info(f"Using generate_custom_voice with speaker: {voice}")
                    audio_values = model.generate_custom_voice(
                        text=text,
                        language="English",
                        speaker=voice,
                        instructions=instruct,
                        speed=speed,
                        temperature=temperature,
                        cfg_scale=cfg_scale
                    )
                elif hasattr(model, "generate_voice_clone"):
                    # Use zero-shot voice cloning (default for Base models)
                    # If no ref_audio is provided, we use a default prompt if the model requires it
                    # or the model might have a built-in default for this method.
                    logger.info(f"Using generate_voice_clone. Ref audio: {ref_audio}")
                    
                    # Ensure we have some reference if required by base model
                    final_ref_audio = ref_audio or "data/tommy.wav" 
                    final_ref_text = ref_text or "Okay, I do believe I am live"
                    
                    audio_values = model.generate_voice_clone(
                        text=text,
                        language="English",
                        ref_audio=final_ref_audio,
                        ref_text=final_ref_text,
                        instructions=instruct,
                        speed=speed,
                        temperature=temperature,
                        cfg_scale=cfg_scale
                    )
                else:
                    # Generic fallback if specific methods are missing but generate exists
                    logger.warning("Specific generate methods missing, trying generic generate.")
                    if hasattr(model, "generate"):
                        audio_values = model.generate(text=text, speed=speed)
                    else:
                        raise AttributeError(f"Model {type(model)} has no supported generation methods.")
            
            # Qwen3 API typically returns (audio, sample_rate) or just audio tensor
            if isinstance(audio_values, tuple):
                wav, model_sr = audio_values
            else:
                wav = audio_values
                model_sr = self.sample_rate
            
            # Ensure wav is on CPU and convert to numpy
            if hasattr(wav, "cpu"):
                wav = wav.cpu().numpy()
            
            # Squeeze to 1D if necessary
            wav = np.squeeze(wav)
            
            # Trim silence for punchy playback
            wav = self.trim_silence(wav)
            
            return wav, model_sr
            
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
