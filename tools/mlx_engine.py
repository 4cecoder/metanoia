import os
import threading
import numpy as np
import mlx.core as mx
from mlx_audio.tts import load as load_tts_model
from mlx_audio.utils import load_audio
from typing import Optional, List, Dict, Union, Any
import logging

# Suppress annoying transformers/tokenizers warnings
os.environ["TOKENIZERS_PARALLELISM"] = "false"
try:
    import transformers
    transformers.logging.set_verbosity_error()
except ImportError:
    pass

# Force GPU device at the start
mx.set_default_device(mx.gpu)

class MLXEngine:
    def __init__(self):
        self.models = {}
        self.model_paths = {
            "speedy": "models/Qwen3-TTS-12Hz-0.6B-Base-8bit",
            "gold": "models/Qwen3-TTS-12Hz-0.6B-Base-bf16",
            "custom": "models/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"
        }
        self.prompt_cache = {} 
        # Generation runs in the server's single GPU worker.  A thread-local
        # context lets the model's reference encoders reuse a voice's cached
        # conditioning without changing mlx-audio's public API.
        self._prompt_context = threading.local()
        self._fast_path_models = set()
        
    @property
    def sample_rate(self):
        return 24000

    def load_models(self, mode: Optional[str] = None):
        """Lazy load models based on requested mode."""
        modes = [mode] if mode else self.model_paths.keys()
        for key in modes:
            if key in self.models: continue
            path = self.model_paths.get(key)
            if path and os.path.exists(path):
                print(f"Loading MLX model: {key} from {path}...")
                model = load_tts_model(path, fix_mistral_regex=True, attn_implementation="sdpa", device_map="mps")
                mx.eval(model.parameters())
                self.models[key] = model
            elif key == "speedy": # Fallback for speedy if 8bit missing
                alt_path = "models/Qwen3-TTS-12Hz-0.6B-Base-bf16"
                if os.path.exists(alt_path):
                    self.load_models("gold")
                    self.models["speedy"] = self.models["gold"]

    def precompute_voice_prompt(self, name: str, audio_path: str, ref_text: Optional[str] = None, mode: str = "speedy"):
        """Pre-calculates reference audio for faster/higher quality cloning."""
        self.load_models(mode)
        model = self.models.get(mode)
        if model is None: return

        if not os.path.exists(audio_path):
            print(f"Warning: Audio for {name} not found at {audio_path}")
            return

        print(f"Pre-computing {mode} prompt for {name}...")
        self._install_prompt_fast_paths(model)
        # Ensure we are using the optimal sample rate
        ref_audio = load_audio(audio_path, sample_rate=model.sample_rate)
        mx.eval(ref_audio)

        # Qwen3-TTS otherwise re-runs both the speech-tokenizer encoder and
        # speaker encoder for every request.  Those tensors depend only on the
        # reference clip, so evaluate them once and reuse them for every
        # five-verse chunk from this voice.
        ref_codes = None
        speaker_embed = None
        if getattr(model, "speech_tokenizer", None) is not None and model.speech_tokenizer.has_encoder:
            encoded_audio = ref_audio
            if encoded_audio.ndim == 1:
                encoded_audio = encoded_audio[None, None, :]
            elif encoded_audio.ndim == 2:
                encoded_audio = encoded_audio[None, :]
            ref_codes = model.speech_tokenizer.encode(encoded_audio)
            mx.eval(ref_codes)

        if getattr(model, "speaker_encoder", None) is not None:
            speaker_embed = model.extract_speaker_embedding(ref_audio)
            mx.eval(speaker_embed)

        self.prompt_cache[name] = {
            "ref_audio": ref_audio,
            "ref_text": ref_text,
            "ref_codes": ref_codes,
            "speaker_embed": speaker_embed,
        }

    def _install_prompt_fast_paths(self, model):
        """Teach mlx-audio's reference calls to use the active cached prompt.

        This is intentionally a small compatibility shim around the installed
        mlx-audio model.  If a future version changes either method, the
        original implementation remains the fallback and voice generation
        still works; it simply loses the conditioning cache until adapted.
        """
        model_id = id(model)
        if model_id in self._fast_path_models:
            return

        speech_tokenizer = getattr(model, "speech_tokenizer", None)
        if speech_tokenizer is not None and hasattr(speech_tokenizer, "encode"):
            original_encode = speech_tokenizer.encode

            def cached_encode(audio, *args, **kwargs):
                prompt = getattr(self._prompt_context, "value", None)
                if prompt is not None and prompt.get("ref_codes") is not None:
                    return prompt["ref_codes"]
                return original_encode(audio, *args, **kwargs)

            speech_tokenizer.encode = cached_encode

        original_extract = getattr(model, "extract_speaker_embedding", None)
        if original_extract is not None:

            def cached_extract(audio, sr=24000, *args, **kwargs):
                prompt = getattr(self._prompt_context, "value", None)
                if prompt is not None and prompt.get("speaker_embed") is not None:
                    return prompt["speaker_embed"]
                return original_extract(audio, sr=sr, *args, **kwargs)

            model.extract_speaker_embedding = cached_extract

        self._fast_path_models.add(model_id)

    def generate(
        self, 
        text: str, 
        mode: str = "speedy",
        voice: str = "Vivian", 
        instruct: Optional[str] = None, 
        speed: float = 1.0,
        ref_audio: Optional[Union[str, mx.array]] = None,
        ref_text: Optional[str] = None,
        temperature: float = 0.5,
        cfg_scale: float = 2.0
    ):
        self.load_models(mode)
        model = self.models.get(mode)
        if model is None:
            self.load_models("speedy")
            model = self.models.get("speedy")
            if model is None: raise RuntimeError(f"MLX model {mode} could not be loaded")

        self._install_prompt_fast_paths(model)

        # Check for cached prompt
        cached = self.prompt_cache.get(voice)
        
        # Prep inputs
        active_ref_audio = ref_audio
        active_ref_text = ref_text
        
        if cached and (mode == "speedy" or mode == "gold"):
            active_ref_audio = cached["ref_audio"]
            active_ref_text = cached["ref_text"]
        elif isinstance(ref_audio, str) and os.path.exists(ref_audio):
            active_ref_audio = load_audio(ref_audio, sample_rate=model.sample_rate)
            mx.eval(active_ref_audio)

        # Dynamic max_tokens prevents the model from generating silence/garbage 
        # and reduces computation cycles. 12Hz = 12 tokens per second.
        # 1 char is roughly 0.15s of speech => ~1.8 tokens per char.
        # We use a tighter bound (3.0 per char + 128 overhead) to prevent long hangs on EOS failure.
        calc_tokens = min(16384, int(len(text) * 3.0) + 128) 

        gen_kwargs = {
            "text": text,
            "voice": voice,
            "speed": speed,
            "ref_audio": active_ref_audio,
            "ref_text": active_ref_text,
            "instruct": instruct,
            "temperature": temperature,
            "cfg_scale": cfg_scale,
            "lang_code": "english", 
            "max_tokens": calc_tokens,
            "verbose": False
        }
        
        import time
        gen_start = time.time()
        self._prompt_context.value = cached
        try:
            results = model.generate(**gen_kwargs)

            audio_chunks = []
            sample_rate = model.sample_rate

            chunk_count = 0
            for result in results:
                audio_chunks.append(result.audio)
                chunk_count += 1
                if chunk_count % 20 == 0:
                    elapsed = time.time() - gen_start
                    print(f"  [MLX] Generated {chunk_count} segments... ({elapsed:.1f}s)")
        finally:
            self._prompt_context.value = None
            
        if not audio_chunks:
            return None, None
            
        # Concatenate and eval on GPU
        full_audio = mx.concatenate(audio_chunks)
        mx.eval(full_audio)
        
        # Convert to numpy for post-processing
        wav = np.array(full_audio)
        
        # Trim silence (leads to much punchier playback)
        wav = self.trim_silence(wav)
        
        return wav, sample_rate

    def trim_silence(self, wav: np.ndarray, threshold: float = 0.005) -> np.ndarray:
        """Removes leading and trailing silence from the audio array with conservative padding."""
        # Find all indices above threshold
        mask = np.abs(wav) > threshold
        if not np.any(mask):
            return wav
            
        start_idx = np.argmax(mask)
        end_idx = len(wav) - np.argmax(mask[::-1])
        
        # Add generous padding (250ms) for naturalness and safety
        # 24000 * 0.25 = 6000 samples
        padding = 6000
        start_idx = max(0, start_idx - padding)
        end_idx = min(len(wav), end_idx + padding)
        
        return wav[start_idx:end_idx]

if __name__ == "__main__":
    engine = MLXEngine()
    engine.load_models()
    if engine.models:
        audio, sr = engine.generate("Testing high fidelity cloning.", mode="base")
        print(f"Generated audio: {len(audio)} samples at {sr}Hz")
