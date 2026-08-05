import os
import time
import threading
from fastapi import APIRouter, Request

from ..core import logger
from ..system import SystemDetector

router = APIRouter()

# Same repo/local-dir pair mlx_engine.py's "gold" mode expects and
# tools/inspection/download_mlx_models.py already downloads manually — this
# just gives the app a way to trigger and track that same download itself.
MLX_MODEL_REPO = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"
MLX_MODEL_LOCAL_DIR = os.path.join("models", "Qwen3-TTS-12Hz-0.6B-Base-bf16")


def _mlx_model_downloaded() -> bool:
    # Mirrors mlx_engine.py's own gating check exactly, so "status" here
    # never disagrees with what the engine will actually try to load.
    return os.path.exists(MLX_MODEL_LOCAL_DIR)


def _dir_size(path: str) -> int:
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def _download_worker(state: dict) -> None:
    from huggingface_hub import HfApi, snapshot_download

    try:
        total_bytes = 0
        try:
            info = HfApi().repo_info(MLX_MODEL_REPO, files_metadata=True)
            total_bytes = sum((s.size or 0) for s in info.siblings)
        except Exception as e:
            logger.warning(f"Could not fetch model size upfront: {e}")

        os.makedirs(MLX_MODEL_LOCAL_DIR, exist_ok=True)

        def poll_progress():
            while state["downloading"]:
                if total_bytes:
                    downloaded = _dir_size(MLX_MODEL_LOCAL_DIR)
                    state["progress_pct"] = min(99.0, downloaded / total_bytes * 100)
                time.sleep(1)

        poll_thread = threading.Thread(target=poll_progress, daemon=True)
        poll_thread.start()

        snapshot_download(repo_id=MLX_MODEL_REPO, local_dir=MLX_MODEL_LOCAL_DIR)
        state["progress_pct"] = 100.0
        logger.info(f"Model download complete: {MLX_MODEL_REPO} -> {MLX_MODEL_LOCAL_DIR}")
    except Exception as e:
        logger.error(f"Model download failed: {e}")
        state["error"] = str(e)
    finally:
        state["downloading"] = False


@router.get("/models/status")
async def get_model_status(request: Request):
    state = request.app.state.model_download
    return {
        "backend": SystemDetector.preferred_backend(),
        "downloaded": _mlx_model_downloaded(),
        "downloading": state["downloading"],
        "progress_pct": state["progress_pct"],
        "error": state["error"],
    }


@router.post("/models/download")
async def start_model_download(request: Request):
    state = request.app.state.model_download
    if state["downloading"]:
        return {"status": "already_downloading"}
    if _mlx_model_downloaded():
        return {"status": "already_downloaded"}

    state["downloading"] = True
    state["error"] = None
    state["progress_pct"] = 0.0
    threading.Thread(target=_download_worker, args=(state,), daemon=True).start()
    return {"status": "started"}
