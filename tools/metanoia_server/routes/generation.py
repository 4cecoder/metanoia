import os
import time
import hashlib
import asyncio
import soundfile as sf
import io as python_io
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, Response

from ..core import TTSRequest, logger
from ..voice_manager import load_voices
from ..cache import TTSCacheManager


router = APIRouter()
gpu_lock = asyncio.Semaphore(1)


def get_engine(request: Request):
    container = request.app.state.container
    engine = container.get_active()
    if not engine:
        raise HTTPException(status_code=503, detail="No TTS engine loaded")
    return engine


def get_cache(request: Request) -> TTSCacheManager:
    return request.app.state.cache


@router.post("/generate")
async def generate_speech(
    tts_request: TTSRequest,
    engine=Depends(get_engine),
    cache_manager: TTSCacheManager = Depends(get_cache),
):
    voices = load_voices()
    selected_voice = tts_request.voice.lower()

    ref_audio = None
    ref_text = None
    mode = tts_request.mode

    if selected_voice in voices:
        cfg = voices[selected_voice]
        ref_audio = cfg.get("audio")
        ref_text = cfg.get("text")
        mode = cfg.get("mode", "speedy")

    cache_key = hashlib.md5(f"{tts_request.text}|{selected_voice}|{tts_request.speed}|{mode}".encode()).hexdigest()
    filename = f"cache/tts_{cache_key}.wav"

    if not tts_request.force_refresh:
        cached = cache_manager.get(cache_key)
        if cached and os.path.exists(cached):
            with open(cached, "rb") as f:
                return Response(content=f.read(), media_type="audio/wav")

    async with gpu_lock:
        start = time.time()
        wav, sr = await asyncio.to_thread(
            engine.generate,
            text=tts_request.text,
            mode=mode,
            voice=selected_voice,
            speed=tts_request.speed,
            ref_audio=ref_audio,
            ref_text=ref_text,
            temperature=tts_request.temperature,
            cfg_scale=tts_request.cfg_scale,
        )

        if wav is None:
            raise HTTPException(status_code=500, detail="Generation failed")

        byte_io = python_io.BytesIO()
        sf.write(byte_io, wav, sr, format="WAV")
        audio_bytes = byte_io.getvalue()

        with open(filename, "wb") as f:
            f.write(audio_bytes)
        cache_manager.add(cache_key, filename, tts_request.text, selected_voice, "hash")

        logger.info(f"Generated {cache_key} in {time.time() - start:.2f}s")
        return Response(content=audio_bytes, media_type="audio/wav")
