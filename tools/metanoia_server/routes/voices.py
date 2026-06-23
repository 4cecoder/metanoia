import os
import uuid
import logging
from fastapi import APIRouter, HTTPException, UploadFile, File, Form
from ..core import VoiceUpsertRequest, logger
from ..voice_manager import load_voices, save_voices
from .. import core

router = APIRouter()

@router.get("/voice_status")
async def get_voice_status():
    voices = load_voices()
    status = {}
    for name, cfg in voices.items():
        audio_path = cfg.get("audio")
        exists = os.path.exists(audio_path) if audio_path else False
        v_type = "premium" if not audio_path else "cloned"
        status[name] = {
            "exists": True if v_type == "premium" else exists,
            "has_sample": exists,
            "display_name": name.replace("_", " ").title(),
            "text": cfg.get("text"),
            "mode": cfg.get("mode", "speedy"),
            "type": v_type
        }
    return status

@router.post("/voices")
async def upsert_voice(request: VoiceUpsertRequest):
    voices = load_voices()
    key = request.name.lower().replace(" ", "_")
    voices[key] = {
        "audio": request.audio or f"data/{key}.wav",
        "text": request.text,
        "mode": request.mode
    }
    save_voices(voices)
    return {"status": "success", "voice": key}

@router.delete("/voices/{voice_name}")
async def delete_voice(voice_name: str):
    voices = load_voices()
    key = voice_name.lower()
    if key in voices:
        del voices[key]
        save_voices(voices)
        return {"status": "success"}
    raise HTTPException(status_code=404, detail="Voice not found")

@router.post("/upload_voice_sample")
async def upload_voice_sample(voice: str = Form(...), file: UploadFile = File(...)):
    voices = load_voices()
    voice = voice.lower()
    if voice not in voices:
        raise HTTPException(status_code=400, detail="Voice not found")
    
    target_path = voices[voice].get("audio") or f"data/{voice}.wav"
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    
    with open(target_path, "wb") as f:
        f.write(await file.read())
    
    voices[voice]["audio"] = target_path
    save_voices(voices)
    return {"status": "success", "path": target_path}
