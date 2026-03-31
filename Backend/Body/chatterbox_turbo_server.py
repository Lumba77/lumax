import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, ConfigDict
import numpy as np
import io
import os
import sys
import soundfile as sf
from fastapi.responses import Response
import logging

# Configure Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ChatterboxTurbo")

# Add the mounted source directory to sys.path
source_dir = "/app/models"
if os.path.exists(source_dir):
    sys.path.append(source_dir)
    logger.info(f"Added {source_dir} to sys.path")

# Direct import to see the error
from xtts_streaming_pipeline import StreamingTTSPipeline

class TTSRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    text: str
    speaker_id: str = "default"

app = FastAPI(title="Lumax Chatterbox Turbo Server")
pipeline = None
latents_cache = {} # Cache for multiple speakers
DEFAULT_SPEAKER = "female_shadowheart"

@app.on_event("startup")
def load_model():
    global pipeline
    logger.info("Initializing XTTS Streaming Pipeline (Source)...")
    
    model_dir = os.path.join(source_dir, "xtts_onnx")
    vocab_path = os.path.join(model_dir, "vocab.json")
    mel_stats_path = os.path.join(model_dir, "mel_stats.npy")
    
    try:
        if not os.path.exists(model_dir):
            logger.error(f"Model directory not found at: {model_dir}")
            return
            
        logger.info(f"Loading Pipeline from {model_dir}...")
        pipeline = StreamingTTSPipeline(model_dir, vocab_path, mel_stats_path, use_int8_gpt=True)
        
        # Pre-load the default speaker
        _get_or_load_latents(DEFAULT_SPEAKER)

        logger.info("XTTS Streaming Pipeline LOADED.")
    except Exception as e:
        logger.error(f"Failed to load pipeline: {e}")

def _get_or_load_latents(speaker_id: str):
    """Helper to load and cache speaker conditioning."""
    if speaker_id in latents_cache:
        return latents_cache[speaker_id]
    
    # Try to find a matching file in audio_ref
    ref_dir = os.path.join(source_dir, "audio_ref")
    possible_extensions = [".flac", ".wav", ".mp3"]
    
    ref_path = None
    # 1. Try exact match (if they provided extension)
    if os.path.exists(os.path.join(ref_dir, speaker_id)):
        ref_path = os.path.join(ref_dir, speaker_id)
    else:
        # 2. Try adding extensions
        for ext in possible_extensions:
            test_path = os.path.join(ref_dir, speaker_id + ext)
            if os.path.exists(test_path):
                ref_path = test_path
                break
    
    # 3. Fallback to default if not found
    if not ref_path:
        logger.warning(f"Speaker '{speaker_id}' not found in {ref_dir}. Falling back to default.")
        if speaker_id == DEFAULT_SPEAKER: return None # Root failure
        return _get_or_load_latents(DEFAULT_SPEAKER)

    try:
        logger.info(f"Computing conditioning for {ref_path}...")
        latents = pipeline.get_conditioning_latents(ref_path)
        latents_cache[speaker_id] = latents
        logger.info(f"Speaker '{speaker_id}' latents CACHED.")
        return latents
    except Exception as e:
        logger.error(f"Failed to load speaker {speaker_id}: {e}")
        return _get_or_load_latents(DEFAULT_SPEAKER)

@app.get("/health")
async def health():
    return {"status": "online" if pipeline else "offline", "engine": "Turbo-Streaming-Pipeline"}

@app.post("/tts")
async def generate_tts(req: TTSRequest):
    if not pipeline:
        raise HTTPException(status_code=500, detail="TTS Pipeline not initialized")
    
    logger.info(f"Turbo Synthesizing for speaker '{req.speaker_id}': {req.text[:50]}...")
    try:
        latents = _get_or_load_latents(req.speaker_id)
        if not latents:
            raise Exception("Could not load speaker latents")
            
        gpt_cond, speaker_emb = latents
        
        # inference_stream yields numpy arrays (audio chunks)
        chunks = []
        for chunk in pipeline.inference_stream(
            text=req.text,
            language="en",
            gpt_cond_latent=gpt_cond,
            speaker_embedding=speaker_emb
        ):
            chunks.append(chunk)
            
        if not chunks:
            raise Exception("No audio chunks generated")
            
        full_audio = np.concatenate(chunks)
        
        buffer = io.BytesIO()
        # XTTS v2 is 24000Hz
        sf.write(buffer, full_audio, 24000, format="WAV")
        
        return Response(content=buffer.getvalue(), media_type="audio/wav")
    except Exception as e:
        logger.error(f"Synthesis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8005)
