import os
import numpy as np
import soundfile as sf
import sqlite3
import io as python_io
from fastapi import FastAPI, HTTPException, Body, UploadFile, File, Form, Response, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, StreamingResponse, JSONResponse
import traceback
from pydantic import BaseModel
from faster_whisper import WhisperModel
import uuid
import logging
import time
import hashlib
import asyncio
import subprocess
import platform
from contextlib import asynccontextmanager
from typing import Optional, Dict, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("metanoia-tts")

# Cache Configuration
CACHE_DIR = "cache"
CACHE_DB = os.path.join(CACHE_DIR, "index.db")
MAX_CACHE_SIZE_MB = 1000 # 1GB
MAX_CACHE_AGE_DAYS = 30

class TTSCacheManager:
    def __init__(self):
        os.makedirs(CACHE_DIR, exist_ok=True)
        self.conn = sqlite3.connect(CACHE_DB, check_same_thread=False)
        self.init_db()
        self.mem_cache: Dict[str, bytes] = {} # Small in-memory cache for very frequent items
        self.max_mem_items = 20

    def init_db(self):
        cursor = self.conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tts_cache (
                key TEXT PRIMARY KEY,
                filename TEXT,
                text TEXT,
                voice TEXT,
                params_hash TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                access_count INTEGER DEFAULT 1,
                file_size INTEGER
            )
        """)
        self.conn.commit()

    def get(self, key: str) -> Optional[str]:
        """Returns filename if exists and updates access stats."""
        cursor = self.conn.cursor()
        cursor.execute("SELECT filename FROM tts_cache WHERE key = ?", (key,))
        row = cursor.fetchone()
        if row:
            filename = row[0]
            if os.path.exists(filename):
                cursor.execute("""
                    UPDATE tts_cache SET 
                    last_accessed = CURRENT_TIMESTAMP, 
                    access_count = access_count + 1 
                    WHERE key = ?
                """, (key,))
                self.conn.commit()
                return filename
            else:
                # File missing but in DB, cleanup
                cursor.execute("DELETE FROM tts_cache WHERE key = ?", (key,))
                self.conn.commit()
        return None

    def add(self, key: str, filename: str, text: str, voice: str, params_hash: str):
        """Adds a new entry to the cache index."""
        file_size = os.path.getsize(filename)
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT OR REPLACE INTO tts_cache 
            (key, filename, text, voice, params_hash, file_size) 
            VALUES (?, ?, ?, ?, ?, ?)
        """, (key, filename, text, voice, params_hash, file_size))
        self.conn.commit()
        # Trigger async pruning check
        self.prune()

    def prune(self):
        """Removes old or least accessed files to stay under size limits."""
        cursor = self.conn.cursor()
        # 1. Prune by Age
        cursor.execute(f"SELECT filename FROM tts_cache WHERE created_at < datetime('now', '-{MAX_CACHE_AGE_DAYS} days')")
        for (f,) in cursor.fetchall():
            if os.path.exists(f): os.remove(f)
        cursor.execute(f"DELETE FROM tts_cache WHERE created_at < datetime('now', '-{MAX_CACHE_AGE_DAYS} days')")

        # 2. Prune by Size (LRU)
        cursor.execute("SELECT SUM(file_size) FROM tts_cache")
        total_size = cursor.fetchone()[0] or 0
        if total_size > MAX_CACHE_SIZE_MB * 1024 * 1024:
            logger.info("Cache size limit reached, pruning oldest entries...")
            cursor.execute("SELECT key, filename, file_size FROM tts_cache ORDER BY last_accessed ASC LIMIT 50")
            for key, f, size in cursor.fetchall():
                if os.path.exists(f): os.remove(f)
                cursor.execute("DELETE FROM tts_cache WHERE key = ?", (key,))
                total_size -= size
                if total_size <= (MAX_CACHE_SIZE_MB * 0.8) * 1024 * 1024: break # Prune down to 80%
        
        self.conn.commit()

# Global instances
mlx_engine = None
torch_engine = None
whisper_model = None
cache_manager = TTSCacheManager()
generation_locks: Dict[str, asyncio.Lock] = {}

def get_engine():
    global mlx_engine, torch_engine
    if mlx_engine: return mlx_engine
    if torch_engine: return torch_engine
    return None

# Multi-threading helpers
from concurrent.futures import ThreadPoolExecutor
executor = ThreadPoolExecutor(max_workers=4)
gpu_semaphore = asyncio.Semaphore(3) # 3 concurrent GPU tasks for maximum throughput

async def check_git_updates():
    """Background task to poll for git updates on the master branch."""
    while True:
        await asyncio.sleep(60) # Poll every minute
        try:
            # Check for updates
            subprocess.run(["git", "fetch", "origin", "master"], check=True, capture_output=True)
            local = subprocess.getoutput("git rev-parse HEAD").strip()
            remote = subprocess.getoutput("git rev-parse origin/master").strip()
            
            if local != remote:
                logger.info("--- Git updates detected on master! Pulling changes... ---")
                
                # Check what files changed
                changed_files = subprocess.getoutput("git diff --name-only HEAD origin/master").split()
                
                # Pull the changes
                subprocess.run(["git", "pull", "origin", "master"], check=True)
                
                # If dependencies changed, sync them
                if any(f in changed_files for f in ["pyproject.toml", "uv.lock", "requirements.txt"]):
                    logger.info("--- Dependency changes detected! Running uv sync... ---")
                    try:
                        # Try uv sync first as it's the preferred method
                        subprocess.run(["uv", "sync"], check=True)
                    except FileNotFoundError:
                        # Fallback to pip if uv is not in PATH (though uv run implies it is)
                        subprocess.run([sys.executable, "-m", "pip", "install", "."], check=True)
                
                # uvicorn with reload=True will detect the file changes and restart the server
        except Exception as e:
            logger.debug(f"Git update check failed: {e}")

def setup_system_deps():
    """Checks and installs system-level dependencies if on Linux/Ubuntu."""
    if platform.system() == "Linux":
        try:
            # Check if sox is installed
            res = subprocess.run(["which", "sox"], capture_output=True)
            if res.returncode != 0:
                logger.info("SoX not found. Attempting to install system dependencies...")
                # Try to install - this assumes the user has sudo rights without password 
                # or is in a shell that allows it.
                subprocess.run(["sudo", "apt-get", "update", "-qq"], check=True)
                subprocess.run(["sudo", "apt-get", "install", "-y", "-qq", "sox", "libsox-fmt-all"], check=True)
                logger.info("System dependencies (SoX) installed successfully.")
            else:
                logger.info("System dependency check: SoX is already installed.")
            
            # Firewall: Allow port 8000 for network access
            try:
                logger.info("Configuring firewall: Allowing port 8000/tcp...")
                subprocess.run(["sudo", "ufw", "allow", "8000/tcp"], check=False, capture_output=True)
            except Exception:
                pass # UFW might not be installed or active
                
        except Exception as e:
            logger.warning(f"Could not automatically install system deps: {e}")
            logger.warning("Please manualy run: sudo apt install -y sox libsox-fmt-all")

# Voice Configurations
VOICE_CONFIGS = {
    "tommy": {
        "audio": "data/tommy.wav",
        "text": "Okay, I do believe I am live"
    },
    "lennox": {
        "audio": "data/lennox_ref.wav",
        "text": "We need to be worried, first of all, about what the AI that's currently working about the ethical problems it leads to. And they are very scary, and the one that scares people most is deception."
    },
    "mari": {
        "audio": "data/mari_ref.wav",
        "text": "we all worship the same God each to their own way shame on you for denying your Lord Jesus the Lord said I am the way no other way no one",
        "mode": "gold",
        "temperature": 0.4,
        "cfg_scale": 2.5
    },
    "jordan": {
        "audio": "data/jordan_ref.wav",
        "text": "Look around and see what bugs you in your room. Do I like this room? No, it bugs me. Why? It's dusty there and the carpet's dirty and that corner's kind of ugly and the light there isn't very good. Okay, pick a problem. Pick a solution to it that you know wouldn't help, that you could do."
    },
    "shamoun": {
        "audio": "data/shamoun_ref.wav",
        "text": "Okay, why didn't Jesus Christ come out and say, I am God? Why didn't Jesus Christ come out and say, I am God? Now, I already have dozens of sessions answering this, articles answering this, but we are creatures of repetition, and we need to hear something.",
        "mode": "gold",
        "temperature": 0.4,
        "cfg_scale": 2.5
    },
    "roumie": {
        "audio": "data/roumie_perfect_15s.wav",
        "text": "I am the way, and the truth, and the life. No one comes to the Father except through me. Ah, there's that word. Soon.",
        "mode": "speedy",
        "temperature": 0.5,
        "cfg_scale": 2.0
    }
    };


@asynccontextmanager
async def lifespan(app: FastAPI):
    global mlx_engine, torch_engine, whisper_model
    
    # Handle system dependencies on Linux
    setup_system_deps()
    
    # Start git polling in the background
    update_task = asyncio.create_task(check_git_updates())
    
    # System Detection
    is_macos = platform.system() == "Darwin"
    has_mlx = False
    
    if is_macos:
        try:
            import mlx.core as mx
            has_mlx = True
            logger.info("Apple Silicon detected. Using MLXEngine.")
        except ImportError:
            logger.info("MLX not found on macOS. Falling back to Torch/CPU.")
    else:
        logger.info(f"Platform: {platform.system()} (WSL/Ubuntu). MLX is disabled. Checking for NVIDIA/CUDA...")

    try:
        engine = None
        if has_mlx:
            from mlx_engine import MLXEngine
            mlx_engine = MLXEngine()
            mlx_engine.load_models()
            engine = mlx_engine
        else:
            # Explicitly use TorchEngine for Linux/WSL or non-MLX Mac
            import torch
            logger.info(f"Torch version: {torch.__version__}")
            if torch.cuda.is_available():
                logger.info(f"NVIDIA GPU detected: {torch.cuda.get_device_name(0)} (CUDA {torch.version.cuda})")
            else:
                logger.warning("No NVIDIA GPU detected. Running on CPU (slow).")
            
            from torch_engine import TorchEngine
            torch_engine = TorchEngine()
            torch_engine.load_models()
            engine = torch_engine
            logger.info("TorchEngine initialized successfully.")

        # Pre-compute prompts for preset voices
        if engine:
            for name, cfg in VOICE_CONFIGS.items():
                precompute_mode = cfg.get("mode", "speedy")
                engine.precompute_voice_prompt(
                    name=name,
                    audio_path=cfg["audio"],
                    ref_text=cfg["text"],
                    mode=precompute_mode
                )

        # Load whisper for auto-transcription support
        logger.info("Loading Faster Whisper (small) for web interface...")
        device = "cpu"
        if has_mlx:
            device = "cpu" # Whisper-Faster doesn't support MPS well yet
        elif torch_engine:
            import torch
            if torch.cuda.is_available(): device = "cuda"
            
        whisper_model = WhisperModel("small", device=device, compute_type="int8")

    except Exception as e:
        logger.error(f"Failed to load engines: {e}")
    yield
    update_task.cancel()
    mlx_engine = None
    torch_engine = None

app = FastAPI(lifespan=lifespan)

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Catch-all for any server error, returning full detail to the client."""
    # Special handling for already-formatted Detail strings (like CUDA errors)
    detail = str(exc)
    
    error_details = {
        "detail": detail,
        "type": type(exc).__name__,
        "traceback": traceback.format_exc(),
        "path": request.url.path
    }
    logger.error(f"NETWORK API ERROR: {error_details['type']} at {error_details['path']}\n{error_details['traceback']}")
    return JSONResponse(
        status_code=500,
        content=error_details
    )

# Create cache and uploads dirs
os.makedirs("cache", exist_ok=True)
os.makedirs("uploads", exist_ok=True)

class TTSRequest(BaseModel):
    text: str
    voice: str = "tommy"
    style: str = "Natural"
    speed: float = 1.0
    emotion: Optional[str] = None
    mode: str = "base"
    force_refresh: bool = False
    temperature: float = 0.5
    cfg_scale: float = 2.0

@app.post("/generate")
async def generate_speech(request: TTSRequest):
    engine = get_engine()
    if engine is None:
        raise HTTPException(status_code=503, detail="TTS Engine not loaded")
    
    # Normalize input
    clean_text = request.text.strip()
    selected_voice = request.voice.lower()
    
    # Check if voice is a preset or needs cloning
    ref_audio = None
    ref_text = None
    mode = request.mode
    temperature = request.temperature
    cfg_scale = request.cfg_scale

    if selected_voice in VOICE_CONFIGS:
        cfg = VOICE_CONFIGS[selected_voice]
        ref_audio = cfg["audio"]
        ref_text = cfg["text"]
        
        # Apply voice-specific overrides
        mode = cfg.get("mode", "speedy" if mode != "gold" else "gold")
        temperature = cfg.get("temperature", temperature)
        cfg_scale = cfg.get("cfg_scale", cfg_scale)
    else:
        # If not a preset cloning voice, maybe it's a CustomVoice speaker name
        if mode != "gold": mode = "custom"

    # Generate a robust cache key including new parameters
    cache_parts = [clean_text, selected_voice, str(request.speed), str(request.emotion), mode, str(temperature), str(cfg_scale)]
    params_hash = "|".join(cache_parts[1:]) # Hash of everything but the text
    cache_key = hashlib.md5("|".join(cache_parts).encode()).hexdigest()
    filename = f"cache/tts_{cache_key}.wav"
    abs_filename = os.path.abspath(filename)
    
    # 1. Use Cache Manager for retrieval
    if not request.force_refresh:
        cached_file = cache_manager.get(cache_key)
        if cached_file:
            try:
                with open(cached_file, "rb") as f:
                    data = f.read()
                logger.info(f"Cache Hit (Memory-Buffered): {cache_key}")
                return Response(content=data, media_type="audio/wav")
            except Exception as e:
                logger.warning(f"Failed to read cache file {cached_file}: {e}")

    if cache_key not in generation_locks:
        generation_locks[cache_key] = asyncio.Lock()
    
    async with generation_locks[cache_key]:
        # Double check after lock
        if not request.force_refresh:
            cached_file = cache_manager.get(cache_key)
            if cached_file and os.path.exists(cached_file):
                with open(cached_file, "rb") as f:
                    return Response(content=f.read(), media_type="audio/wav")

        logger.info(f"Cache Miss. Generating for key {cache_key} (Mode: {mode})...")
        start_time = time.time()
        
        async with gpu_semaphore:
            try:
                # Generate via Engine in a separate thread to avoid blocking the event loop
                wav, sr = await asyncio.to_thread(
                    engine.generate,
                    text=clean_text,
                    mode=mode,
                    voice=request.voice if mode == "custom" else selected_voice,
                    instruct=request.emotion,
                    speed=request.speed,
                    ref_audio=ref_audio,
                    ref_text=ref_text,
                    temperature=temperature,
                    cfg_scale=cfg_scale
                )
                
                if wav is None:
                    raise ValueError("TTS generation failed")

                gen_duration = time.time() - start_time
                logger.info(f"Generation took {gen_duration:.2f}s for {len(clean_text)} chars")

                # 2. Save to Cache Manager index & disk
                import io as python_io
                byte_io = python_io.BytesIO()
                sf.write(byte_io, wav, sr, format='WAV')
                audio_bytes = byte_io.getvalue()
                
                temp_filename = f"{filename}.tmp"
                with open(temp_filename, "wb") as f:
                    f.write(audio_bytes)
                os.replace(temp_filename, filename)
                
                cache_manager.add(cache_key, filename, clean_text, selected_voice, params_hash)
                
                elapsed = time.time() - start_time
                logger.info(f"Generation Complete: {cache_key} in {elapsed:.2f}s")
                
                return Response(content=audio_bytes, media_type="audio/wav")
            except Exception as e:
                logger.error(f"Generation error for {cache_key}: {e}")
                raise HTTPException(status_code=500, detail=str(e))

@app.get("/voice_status")
async def get_voice_status():
    """Check which preset voice reference files exist on the server."""
    status = {}
    for name, cfg in VOICE_CONFIGS.items():
        exists = os.path.exists(cfg["audio"])
        status[name] = {
            "exists": exists,
            "path": cfg["audio"],
            "filename": os.path.basename(cfg["audio"]),
            "display_name": name.capitalize() if name != "roumie" else "Jonathan Roumie"
        }
    return status

@app.post("/upload_voice_sample")
async def upload_voice_sample(
    file: UploadFile = File(...),
    voice: str = Form(...)
):
    """Upload a reference WAV file for a preset voice (e.g. lennox, tommy)."""
    voice = voice.lower()
    if voice not in VOICE_CONFIGS:
        raise HTTPException(status_code=400, detail=f"Voice '{voice}' is not a recognized preset.")
    
    if not file.filename.endswith(".wav"):
        raise HTTPException(status_code=400, detail="Only .wav files are supported for voice samples.")

    target_path = VOICE_CONFIGS[voice]["audio"]
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    
    try:
        content = await file.read()
        with open(target_path, "wb") as f:
            f.write(content)
        
        logger.info(f"Updated reference audio for {voice} at {target_path}")
        
        # Invalidate any pre-computed prompts for this voice
        engine = get_engine()
        if engine and hasattr(engine, "prompt_cache"):
            if voice in engine.prompt_cache:
                del engine.prompt_cache[voice]
                logger.info(f"Invalidated prompt cache for {voice}")
                
        return {"status": "success", "message": f"Uploaded sample for {voice}", "path": target_path}
    except Exception as e:
        logger.error(f"Failed to upload voice sample: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/stream")
async def stream_speech(
    text: str,
    voice: str = "tommy",
    speed: float = 1.0,
    emotion: Optional[str] = None,
    mode: str = "base",
    temperature: float = 0.5,
    cfg_scale: float = 2.0
):
    """Streaming endpoint for low-latency network playback."""
    engine = get_engine()
    if engine is None:
        raise HTTPException(status_code=503, detail="TTS Engine not loaded")

    # Resolve voice config for preset overrides
    selected_voice = voice.lower()
    ref_audio = None
    ref_text = None
    if selected_voice in VOICE_CONFIGS:
        cfg = VOICE_CONFIGS[selected_voice]
        ref_audio = cfg["audio"]
        ref_text = cfg["text"]
        mode = cfg.get("mode", "speedy" if mode != "gold" else "gold")
        temperature = cfg.get("temperature", temperature)
        cfg_scale = cfg.get("cfg_scale", cfg_scale)

    async def audio_generator():
        # This requires the engine.generate to be a generator or modified to yield
        # For now, we'll simulate streaming by yielding the full result in chunks
        # if the engine doesn't support true chunked yielding yet.
        wav, sr = await asyncio.to_thread(
            engine.generate,
            text=text,
            mode=mode,
            voice=voice if mode == "custom" else selected_voice,
            instruct=emotion,
            speed=speed,
            ref_audio=ref_audio,
            ref_text=ref_text,
            temperature=temperature,
            cfg_scale=cfg_scale
        )
        
        # Convert to WAV in memory but stream the bytes
        import io as python_io
        byte_io = python_io.BytesIO()
        sf.write(byte_io, wav, sr, format='WAV')
        data = byte_io.getvalue()
        
        # Yield in 16KB chunks
        chunk_size = 16384
        for i in range(0, len(data), chunk_size):
            yield data[i:i + chunk_size]

    return StreamingResponse(audio_generator(), media_type="audio/wav")

@app.post("/transcribe")
async def api_transcribe(file: UploadFile = File(...)):
    if whisper_model is None:
        raise HTTPException(status_code=503, detail="Whisper model not loaded")
    
    temp_path = f"uploads/transcribe_{uuid.uuid4().hex}_{file.filename}"
    with open(temp_path, "wb") as f:
        f.write(await file.read())
    
    try:
        logger.info(f"Auto-transcribing uploaded file: {file.filename}")
        segments, info = whisper_model.transcribe(temp_path, beam_size=5, vad_filter=True)
        text = " ".join([s.text for s in segments]).strip()
        os.remove(temp_path)
        return {"text": text, "language": info.language}
    except Exception as e:
        if os.path.exists(temp_path): os.remove(temp_path)
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/clone_dynamic")
async def clone_dynamic(
    file: UploadFile = File(...),
    text: str = Form(...),
    ref_text: Optional[str] = Form(None),
    emotion: Optional[str] = Form(None),
    speed: float = Form(1.0)
):
    engine = get_engine()
    if engine is None:
        raise HTTPException(status_code=503, detail="TTS Engine not loaded")

    # Save uploaded reference
    ref_id = uuid.uuid4().hex
    ref_path = f"uploads/{ref_id}_{file.filename}"
    with open(ref_path, "wb") as f:
        f.write(await file.read())

    logger.info(f"Dynamic Clone: Received {file.filename}, generating target text...")
    
    try:
        # Generate via Engine
        wav, sr = engine.generate(
            text=text,
            mode="base",
            ref_audio=ref_path,
            ref_text=ref_text,
            instruct=emotion,
            speed=speed
        )

        if wav is None:
            raise ValueError("TTS generation failed")

        out_filename = f"cache/dynamic_{ref_id}.wav"
        sf.write(out_filename, wav, sr, format='WAV')
        
        # Cleanup upload
        os.remove(ref_path)
        
        return FileResponse(os.path.abspath(out_filename), media_type="audio/wav")
    except Exception as e:
        logger.error(f"Dynamic clone error: {e}")
        if os.path.exists(ref_path): os.remove(ref_path)
        raise HTTPException(status_code=500, detail=str(e))

# Mount static files for the web interface
app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/")
async def serve_index():
    from fastapi.responses import FileResponse
    response = FileResponse("static/index.html")
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    return response

if __name__ == "__main__":
    import uvicorn
    import sys
    import socket
    import os
    
    # Debug CUDA asserts
    os.environ["CUDA_LAUNCH_BLOCKING"] = "1"
    
    def get_local_ip():
        try:
            # Create a dummy socket to detect the primary network interface IP
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return "127.0.0.1"

    # Ensure the tools directory is in the path so uvicorn can find the module
    tools_dir = os.path.dirname(os.path.abspath(__file__))
    if tools_dir not in sys.path:
        sys.path.insert(0, tools_dir)
        
    local_ip = get_local_ip()
    port = 8000
    
    print("\n" + "="*50)
    print(f"Metanoia TTS Server is starting!")
    print(f"Local Access: http://127.0.0.1:{port}")
    print(f"Network Access: http://{local_ip}:{port}")
    print("="*50 + "\n")
    
    logger.info("Starting TTS Server with UV Run compatibility and auto-reload...")
    # Use string-based loading for reload support
    # Bind to 0.0.0.0 to allow network streaming
    uvicorn.run("tts_server:app", host="0.0.0.0", port=port, reload=True, reload_dirs=[tools_dir])
