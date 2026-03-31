import os
import sys
import logging
import base64
import tempfile
from typing import List, Dict, Optional, Any
from fastapi import FastAPI, HTTPException, Request, Response
from pydantic import BaseModel, ConfigDict
import httpx

from fastapi.middleware.cors import CORSMiddleware

# Configure Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("BodyInterface")

app = FastAPI(title="Lumax Body Interface")

# --- CORS Configuration ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Environment State
MODE = os.getenv("MODE", "EARS") # Default to EARS if not set
CHATTERBOX_URL = "http://lumax_chatterbox:8020"
TURBO_URL = "http://lumax_chatterbox_turbo:8005"

# --- Whisper Model Initialization (Only in EARS mode to save VRAM) ---
whisper_model = None
if MODE == "EARS":
    import torch
    device = "cuda" if torch.cuda.is_available() else "cpu"
    compute_type = "float16" if device == "cuda" else "int8"
    
    logger.info(f"Initializing Faster-Whisper Model on {device.upper()} (base.en)...")
    try:
        from faster_whisper import WhisperModel
        whisper_model = WhisperModel("base.en", device=device, compute_type=compute_type)
        logger.info(f"Faster-Whisper Model Ready ({device.upper()}).")
    except Exception as e:
        logger.error(f"Failed to load Faster-Whisper: {e}")
        try:
            whisper_model = WhisperModel("base.en", device="cpu", compute_type="int8")
            logger.info("Faster-Whisper Fallback to CPU Ready.")
        except:
            logger.error("Faster-Whisper Critical Failure.")

class TTSRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    text: str
    voice: str = "female"
    engine: str = "CHATTERBOX"

class STTRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    audio_base64: str

@app.get("/health")
async def health_check():
    return {"status": "online", "mode": MODE}

@app.post("/stt")
async def handle_stt(request: STTRequest):
    """Bridge for Speech-to-Text"""
    if MODE != "EARS":
        raise HTTPException(status_code=400, detail="Node not in EARS mode")
    if not whisper_model:
        return {"text": "[STT Offline - Model Failed to Load]"}
    try:
        audio_data = base64.b64decode(request.audio_base64)
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_audio:
            temp_audio.write(audio_data)
            temp_file_path = temp_audio.name
        segments, info = whisper_model.transcribe(temp_file_path, beam_size=5, language="en")
        transcription = " ".join([segment.text for segment in segments]).strip()
        os.unlink(temp_file_path)
        if not transcription:
            return {"text": ""}
        logger.info(f"Transcribed Text: {transcription}")
        return {"text": transcription}
    except Exception as e:
        logger.error(f"STT Error: {e}")
        return {"text": f"[STT Error: {str(e)[:50]}]"}

@app.post("/tts")
async def handle_tts(request: TTSRequest):
    """Bridge for Text-to-Speech"""
    if MODE != "MOUTH":
        raise HTTPException(status_code=400, detail="Node not in MOUTH mode")
    
    logger.info(f"TTS Request: {request.text} (Engine: {request.engine})")
    engine_to_use = request.engine
    
    try:
        async with httpx.AsyncClient() as client:
            # TURBO FALLBACK LOGIC
            if engine_to_use == "TURBO":
                try:
                    target = f"{TURBO_URL}/tts"
                    payload = {"text": request.text, "speaker_id": request.voice}
                    logger.info(f"Mouth: Attempting TURBO at {target}")
                    resp = await client.post(target, json=payload, timeout=5.0)
                    if resp.status_code != 200:
                        logger.warning("TURBO engine returned error, falling back to CHATTERBOX")
                        engine_to_use = "CHATTERBOX"
                    else:
                        return Response(content=resp.content, media_type="audio/wav")
                except Exception as e:
                    logger.warning(f"TURBO engine connection failed ({e}), falling back to CHATTERBOX")
                    engine_to_use = "CHATTERBOX"

            # STABLE CHATTERBOX (Port 8020)
            if engine_to_use == "CHATTERBOX":
                target = f"{CHATTERBOX_URL}/tts"
                payload = {"text": request.text, "speaker_wav": request.voice, "language": "en"}
                logger.info(f"Mouth: Forwarding to {target}")
                resp = await client.post(target, json=payload, timeout=120.0)
                if resp.status_code != 200:
                    raise HTTPException(status_code=resp.status_code, detail=f"TTS Engine (CHATTERBOX) error")
                return Response(content=resp.content, media_type="audio/wav")
                
    except Exception as e:
        logger.error(f"TTS Failure: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    port = 8001 if MODE == "EARS" else 8002
    uvicorn.run(app, host="0.0.0.0", port=port)
