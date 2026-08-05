import uvicorn
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from contextlib import asynccontextmanager

from .core import ensure_dirs, logger
from .cache import TTSCacheManager
from .voice_manager import load_voices
from .engine_loader import EngineContainer, load_engines
from .routes import voices, generation, models
from .system import SystemDetector


@asynccontextmanager
async def lifespan(app: FastAPI):
    ensure_dirs()
    v_configs = load_voices()
    container = EngineContainer()
    cache = TTSCacheManager()
    load_engines(container, v_configs)
    app.state.container = container
    app.state.cache = cache
    app.state.model_download = {"downloading": False, "progress_pct": 0.0, "error": None}
    yield
    cache.close()


app = FastAPI(lifespan=lifespan)

app.include_router(voices.router)
app.include_router(generation.router)
app.include_router(models.router)

app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/")
async def serve_index():
    return FileResponse("static/index.html")


@app.get("/system_info")
async def get_system_info():
    return SystemDetector.summary()


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
