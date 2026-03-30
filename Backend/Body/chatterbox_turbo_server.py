import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, ConfigDict
try:
    from chatterbox import ChatterboxTTS
except ImportError:
    # Fallback or informative error for development
    ChatterboxTTS = None
import numpy as np
import io
import soundfile as sf
from fastapi.responses import Response
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ChatterboxTurbo")

app = FastAPI(title="Lumax Chatterbox Turbo Server")
tts = None

class TTSRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    text: str
    speaker_id: str = "default"

@app.on_event("startup")
def load_model():
    global tts
    logger.info("Initializing Chatterbox Turbo Model...")
    try:
        if ChatterboxTTS:
            tts = ChatterboxTTS()
            logger.info("Chatterbox Turbo Model LOADED.")
        else:
            logger.error("Chatterbox library not found in environment!")
    except Exception as e:
        logger.error(f"Failed to load model: {e}")

@app.get("/health")
async def health():
    return {"status": "online" if tts else "offline", "engine": "Turbo"}

@app.post("/tts")
async def generate_tts(req: TTSRequest):
    if not tts:
        raise HTTPException(status_code=500, detail="TTS Engine not initialized")
    
    logger.info(f"Synthesizing: {req.text[:50]}...")
    try:
        # Standard Chatterbox synthesis
        audio = tts.synthesize(req.text)
        buffer = io.BytesIO()
        # Chatterbox usually outputs 22050Hz
        sf.write(buffer, audio, 22050, format="WAV")
        return Response(content=buffer.getvalue(), media_type="audio/wav")
    except Exception as e:
        logger.error(f"Synthesis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8005)
