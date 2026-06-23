import logging
import os
import platform
import sqlite3
from pydantic import BaseModel
from typing import Optional, Dict, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("metanoia-server")

# Shared Models
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

class VoiceUpsertRequest(BaseModel):
    name: str
    text: Optional[str] = None
    mode: str = "speedy"
    audio: Optional[str] = None

# Paths
CACHE_DIR = "cache"
CACHE_DB = os.path.join(CACHE_DIR, "index.db")
VOICES_FILE = "data/voices.json"
UPLOADS_DIR = "uploads"

def ensure_dirs():
    os.makedirs(CACHE_DIR, exist_ok=True)
    os.makedirs(UPLOADS_DIR, exist_ok=True)
    os.makedirs("data", exist_ok=True)
