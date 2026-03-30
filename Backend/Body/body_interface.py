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
    logger.info("Initializing Faster-Whisper Model on CPU (base.en)...")
    try:
        from faster_whisper import WhisperModel
        # Using "base.en" for reliable English accuracy on CPU.
        whisper_model = WhisperModel("base.en", device="cpu", compute_type="int8")
        logger.info("Faster-Whisper Model Ready (base.en).")
    except Exception as e:
        logger.error(f"Failed to load Faster-Whisper: {e}")

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
        
        # Save to temporary file for Whisper to process
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_audio:
            temp_audio.write(audio_data)
            temp_file_path = temp_audio.name
            
        logger.info(f"Processing STT Audio ({len(audio_data)} bytes)...")
        # Explicitly set language to 'en' for speed and accuracy
        segments, info = whisper_model.transcribe(temp_file_path, beam_size=5, language="en")
        
        transcription = " ".join([segment.text for segment in segments]).strip()
        
        # Cleanup
        os.unlink(temp_file_path)
        
        if not transcription:
            logger.info("STT: No speech detected in segment.")
            return {"text": ""}

        logger.info(f"Transcribed Text: {transcription} (Confidence: {info.language_probability:.2f})")
        return {"text": transcription}
        
    except Exception as e:
        logger.error(f"STT Error: {e}")
        return {"text": f"[STT Error: {str(e)[:50]}]"}

@app.post("/tts")
async def handle_tts(request: TTSRequest):
    """Bridge for Text-to-Speech"""
    if MODE != "MOUTH":
        raise HTTPException(status_code=400, detail="Node not in MOUTH mode")
    
    logger.info(f"TTS Request: {request.text}")
    
    engine_url = TURBO_URL if request.engine == "TURBO" else CHATTERBOX_URL
    
    try:
        async with httpx.AsyncClient() as client:
            if request.engine == "TURBO":
                target = f"{TURBO_URL}/tts"
                payload = {"text": request.text, "voice": request.voice}
            else:
                target = f"{CHATTERBOX_URL}/tts_to_audio/"
                payload = {"text": request.text, "speaker_wav": request.voice, "language": "en"}
                
            logger.info(f"Forwarding to {target} with payload {payload}")
            
            resp = await client.post(
                target,
                json=payload,
                timeout=120.0
            )
            
            if resp.status_code != 200:
                raise HTTPException(status_code=resp.status_code, detail="TTS Engine error")
                
            return Response(content=resp.content, media_type="audio/wav")
            
    except Exception as e:
        logger.error(f"TTS Failure: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    port = 8001 if MODE == "EARS" else 8002
    uvicorn.run(app, host="0.0.0.0", port=port)
