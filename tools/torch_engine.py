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
        # Modern NVIDIA GPUs (RTX 30/40) are much more stable with bfloat16
        self.dtype = torch.bfloat16 if self.device == "cuda" else torch.float32
        self.model_paths = {
            "speedy": "Qwen/Qwen3-TTS-12Hz-0.6B-Base",
            "gold": "Qwen/Qwen3-TTS-12Hz-0.6B-Base",
            "custom": "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice"
        }
        self.prompt_cache = {}
        self.tensor_cache = {} # Cache for loaded/resampled audio tensors

    def load_models(self, mode: Optional[str] = None):
        """Lazy load models based on requested mode using Transformers/Torch."""
        try:
            from qwen_tts import Qwen3TTSModel
            
            # Optimization: Use built-in SDPA (Scaled Dot Product Attention) 
            # as the baseline for all modern GPUs. It's much faster than 'eager'.
            attn_implementation = "sdpa" 
            
            if self.device == "cuda":
                try:
                    import flash_attn
                    attn_implementation = "flash_attention_2"
                    logger.info("Flash Attention 2 detected and enabled.")
                except ImportError:
                    logger.info("Flash Attention not found. Using optimized PyTorch SDPA.")

            modes = [mode] if mode else ["speedy"]
            for key in modes:
                if key in self.models: continue
                model_id = self.model_paths.get(key)
                logger.info(f"Loading Torch model {key} on {self.device} (Attn: {attn_implementation})...")
                
                # Load with explicit optimizations
                model = Qwen3TTSModel.from_pretrained(
                    model_id,
                    torch_dtype=self.dtype,
                    attn_implementation=attn_implementation
                )
                
                # Explicitly move to device to ensure no lazy CPU residency
                model.to(self.device)
                self.models[key] = model
                logger.info(f"Model {key} is now resident on {self.device}")
        except ImportError:
            logger.error("torch_engine: 'qwen_tts' package not found. Please install the Qwen3-TTS torch implementation.")
            raise RuntimeError("TorchEngine requires 'qwen_tts' package for NVIDIA/CUDA support.")

    def precompute_voice_prompt(self, name: str, audio_path: str, ref_text: Optional[str] = None, mode: str = "speedy"):
        """Pre-calculates reference audio for faster/higher quality cloning."""
        if not os.path.exists(audio_path):
            return

        # Ensure the model for this mode is loaded
        if mode not in self.models:
            self.load_models(mode)

        model = self.models[mode]
        logger.info(f"Pre-caching voice: {name} (Mode: {mode})")

        try:
            with torch.no_grad():
                # 1. Try to extract high-level speaker prompt (best for speed)
                prompt = None
                if hasattr(model, "get_speaker_prompt"):
                    prompt = model.get_speaker_prompt(ref_audio=audio_path, ref_text=ref_text)
                elif hasattr(model, "preprocess_ref_audio"):
                    prompt = model.preprocess_ref_audio(ref_audio=audio_path, ref_text=ref_text)

                if prompt is not None:
                    self.prompt_cache[name] = prompt
                    logger.info(f"Successfully cached speaker prompt for {name}")
                    return

                # 2. Fallback: Cache the processed audio array to skip Disk IO/Resampling
                import librosa
                audio, _ = librosa.load(audio_path, sr=self.sample_rate)
                # Cache as numpy array because the model API expects it
                self.tensor_cache[name] = audio
                logger.info(f"Successfully cached audio array for {name} (RAM resident, IO bypassed)")

        except Exception as e:
            logger.warning(f"Could not pre-cache {name}: {e}")


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
        
        # --- GPU ENFORCEMENT CHECK ---
        if self.device == "cuda":
            # Handle specialized model classes that might hide parameters in sub-modules
            param_source = None
            if hasattr(model, "parameters"):
                param_source = model
            elif hasattr(model, "model") and hasattr(model.model, "parameters"):
                param_source = model.model
            elif hasattr(model, "talker") and hasattr(model.talker, "parameters"):
                param_source = model.talker
                
            if param_source:
                model_device = next(param_source.parameters()).device
                if model_device.type != 'cuda':
                    logger.error(f"STALEMATE: Model {mode} is on {model_device}, but system requires CUDA.")
                    raise RuntimeError(f"GPU Enforcement Failed: Model {mode} is not resident on RTX 4090.")
            else:
                logger.warning(f"Could not verify device for model class {type(model).__name__}. Proceeding with caution.")
        # -----------------------------

        # Check if we have a cached prompt or tensor for this voice
        voice_key = voice.lower()
        cached_prompt = self.prompt_cache.get(voice_key)
        cached_tensor = self.tensor_cache.get(voice_key)
        
        logger.info(f"Generating Torch audio using mode: {mode} (Model: {self.model_paths.get(mode)})")

        # Safety: Sanitize text (remove non-standard chars that might confuse the tokenizer)
        import re
        text = re.sub(r'[^\x00-\x7F]+', ' ', text) # Remove non-ASCII for now
        
        # Safety: Truncate text if it's exceptionally long to avoid CUDA asserts
        # Qwen3-TTS usually handles up to 512 tokens. 350 chars is a very safe limit.
        if len(text) > 350:
            logger.warning(f"Text too long ({len(text)} chars). Truncating to 350 to avoid CUDA assert.")
            text = text[:350]

        logger.info(f"Generating Torch audio for sanitized text ({len(text)} chars)...")
        
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

        import time
        t0 = time.time()
        
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
                    # Use zero-shot voice cloning
                    # Priority 1: High-level prompt (10x speedup)
                    # Priority 2: Pre-loaded tensor (3x speedup)
                    # Priority 3: Disk load (slowest)
                    
                    gen_args = {
                        "text": text,
                        "language": "English",
                        "instructions": instruct,
                        "speed": speed,
                        "temperature": temperature,
                        "cfg_scale": cfg_scale
                    }

                    if cached_prompt is not None:
                        logger.info(f"Using CACHED speaker prompt for {voice}")
                        gen_args["speaker_prompt"] = cached_prompt
                    elif cached_tensor is not None:
                        logger.info(f"Using CACHED audio array for {voice} (Disk IO bypassed)")
                        # API expects (waveform, sample_rate) for numpy input
                        gen_args["ref_audio"] = (cached_tensor, self.sample_rate)
                        gen_args["ref_text"] = ref_text
                    else:
                        logger.info(f"Using slow-path (Disk IO) for {voice}")
                        final_ref_audio = ref_audio or "data/tommy.wav" 
                        final_ref_text = ref_text or "Okay, I do believe I am live"
                        
                        if not os.path.exists(final_ref_audio):
                            raise FileNotFoundError(f"Reference audio not found: {final_ref_audio}")
                        
                        # Load as numpy array and package with sample rate
                        import librosa
                        audio, _ = librosa.load(final_ref_audio, sr=self.sample_rate)
                        gen_args["ref_audio"] = (audio, self.sample_rate)
                        gen_args["ref_text"] = final_ref_text

                    logger.info("Triggering model.generate_voice_clone...")
                    inference_start = time.time()
                    audio_values = model.generate_voice_clone(**gen_args)
                    logger.info(f"Model inference call took {time.time() - inference_start:.2f}s")
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
