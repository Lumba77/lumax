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
logger.info("BodyInterface process MODE=%s (EARS=STT/whisper, MOUTH=TTS/forward)", MODE)

# Docker DNS names (same compose network). Do not hardcode 172.x — subnet changes per bridge.
# Optional full XTTS on 8020: set CHATTERBOX_URL if you add a separate XTTS service (not in default compose).
TURBO_URL = os.getenv("TURBO_URL", "http://lumax_turbochat:8005").rstrip("/")
CHATTERBOX_URL = os.getenv("CHATTERBOX_URL", "").rstrip("/")
# Turbo ONNX / first GPU inference often exceeds 15s; short read timeout looked like "unreachable" in logs.
_TURBO_CONNECT_TIMEOUT = float(os.getenv("TURBO_HTTP_CONNECT_TIMEOUT", "10"))
_TURBO_READ_TIMEOUT = float(os.getenv("TURBO_HTTP_READ_TIMEOUT", "180"))


def _turbo_client_timeout() -> httpx.Timeout:
    return httpx.Timeout(connect=_TURBO_CONNECT_TIMEOUT, read=_TURBO_READ_TIMEOUT)
# Extra fallbacks, e.g. host.docker.internal or a LAN IP — comma-separated base URLs without /tts
def _extra_tts_bases(env_name: str) -> List[str]:
    raw = os.getenv(env_name, "").strip()
    if not raw:
        return []
    return [u.rstrip("/") for u in raw.split(",") if u.strip()]

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

_DEFAULT_TTS_ENGINE = os.getenv("DEFAULT_TTS_ENGINE", os.getenv("TTS_ENGINE", "TURBO"))


class TTSRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    text: str
    voice: str = "female"
    engine: str = _DEFAULT_TTS_ENGINE

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
    
    def _turbo_tts_targets() -> List[str]:
        bases = [TURBO_URL] + _extra_tts_bases("TURBO_EXTRA_URLS")
        return [f"{b}/tts" for b in bases if b]

    def _legacy_xtts_targets() -> List[str]:
        if not CHATTERBOX_URL:
            return []
        bases = [CHATTERBOX_URL] + _extra_tts_bases("CHATTERBOX_EXTRA_URLS")
        return [f"{b}/tts" for b in bases if b]

    try:
        async with httpx.AsyncClient() as client:
            # TURBO PRIMARY (same API as turbochat_server: speaker_id)
            if engine_to_use == "TURBO":
                for target in _turbo_tts_targets():
                    try:
                        payload = {"text": request.text, "speaker_id": request.voice}
                        logger.info(
                            f"Mouth: Attempting TURBO at {target} (read timeout {_TURBO_READ_TIMEOUT}s)"
                        )
                        resp = await client.post(target, json=payload, timeout=_turbo_client_timeout())
                        if resp.status_code == 200:
                            return Response(content=resp.content, media_type="audio/wav")
                        body_preview = (resp.text or "")[:200]
                        logger.warning(
                            f"TURBO target {target} returned status {resp.status_code}: {body_preview}"
                        )
                    except Exception as e:
                        logger.warning(f"Failed to reach TURBO {target}: {type(e).__name__}: {e}")
                
                logger.warning("All TURBO attempts failed. Falling back to CHATTERBOX...")
                engine_to_use = "CHATTERBOX"

            # CHATTERBOX: try turbo surrogate (fast), then optional legacy XTTS on CHATTERBOX_URL, then Piper
            if engine_to_use == "CHATTERBOX":
                logger.info("Mouth: CHATTERBOX requested. Attempting TURBO surrogate first...")
                for target in _turbo_tts_targets():
                    try:
                        payload = {"text": request.text, "speaker_id": request.voice}
                        resp = await client.post(target, json=payload, timeout=_turbo_client_timeout())
                        if resp.status_code == 200:
                            logger.info(f"Mouth: TURBO surrogate OK via {target}.")
                            return Response(content=resp.content, media_type="audio/wav")
                        logger.warning(
                            f"Mouth: TURBO surrogate HTTP {resp.status_code} from {target}: {(resp.text or '')[:200]}"
                        )
                    except Exception as te:
                        logger.warning(
                            f"Mouth: TURBO surrogate attempt at {target} failed: {type(te).__name__}: {te}"
                        )
                
                xtts_targets = _legacy_xtts_targets()
                if xtts_targets:
                    for target in xtts_targets:
                        try:
                            payload = {"text": request.text, "speaker_wav": request.voice, "language": "en"}
                            logger.info(f"Mouth: Forwarding to legacy XTTS at {target}")
                            resp = await client.post(target, json=payload, timeout=45.0)
                            if resp.status_code == 200:
                                return Response(content=resp.content, media_type="audio/wav")
                            logger.warning(f"XTTS target {target} returned status {resp.status_code}")
                        except Exception as e:
                            logger.warning(f"Failed to reach XTTS {target}: {e}")
                else:
                    logger.info("Mouth: CHATTERBOX_URL unset — skipping legacy XTTS container (see docker-compose).")
                
                logger.warning("All XTTS attempts failed. Attempting PIPER fallback...")
                engine_to_use = "PIPER"

            # PIPER LOCAL SYNTHESIS
            if engine_to_use == "PIPER":
                try:
                    import subprocess
                    model_path = os.getenv("PIPER_MODEL_PATH", "/app/models/Mouth/en_US-amy-medium.onnx")
                    if not os.path.exists(model_path):
                        raise Exception(f"Piper model missing at {model_path}")
                    
                    cmd = ["piper", "--model", model_path, "--output_raw"]
                    process = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    stdout, stderr = process.communicate(input=request.text.encode('utf-8'))
                    
                    if process.returncode != 0:
                        raise Exception(f"Piper process error: {stderr.decode()}")
                    
                    return Response(content=stdout, media_type="audio/wav")
                except Exception as e:
                    logger.error(f"Piper synthesis failed: {e}")
                    raise HTTPException(status_code=500, detail=f"All TTS engines failed. Piper Error: {str(e)}")
                
    except Exception as e:
        logger.error(f"TTS Failure: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    port = 8001 if MODE == "EARS" else 8002
    uvicorn.run(app, host="0.0.0.0", port=port)
