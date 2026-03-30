import os
import json
import base64
import logging
import asyncio
import re
import psutil
import time
from typing import List, Dict, Optional, Any
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, ConfigDict
import httpx
from memory import RedisMemory, VectorMemory
from MindCore import MindCore
from HomeCore import HomeCore
from lumax_engine import LumaxEngine
from fastapi.middleware.cors import CORSMiddleware

# --- Configuration ---
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
logging.basicConfig(level=LOG_LEVEL)
logger = logging.getLogger("compagent")
START_TIME = time.time() 
ERROR_COUNT = [0]
LAST_NET = psutil.net_io_counters()
LAST_NET_TIME = time.time()

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://lumax_soul:11434")
OLLAMA_MAIN_MODEL = os.getenv("OLLAMA_MAIN_MODEL", "qwen2.5:latest")
OLLAMA_VISION_MODEL = os.getenv("OLLAMA_VISION_MODEL", "moondream:latest")
SMOLLM_HELPER_MODEL = os.getenv("SMOLLM_HELPER_MODEL", "smollm2:latest")
OLLAMA_EMBED_MODEL = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text:latest")

REDIS_HOST = os.getenv("REDIS_HOST", "lumax_memory")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))

TTS_SERVICE_URL = os.getenv("TTS_SERVICE_URL", "http://lumax_mouth:8002/tts")
TTS_ENGINE = os.getenv("TTS_ENGINE", "CHATTERBOX")
STT_SERVICE_URL = os.getenv("STT_SERVICE_URL", "http://lumax_ears:8001/stt")

# Global Resource Lock for sequential execution
VRAM_LOCK = asyncio.Lock()

# Initialize Multi-Engine Router
MODEL_BASE_PATH = os.getenv("LUMAX_MODEL_DIR", "/app/models")
DEFAULT_MODEL = os.getenv("LUMAX_MODEL_PATH", os.path.join(MODEL_BASE_PATH, "default.gguf"))
engine = LumaxEngine(DEFAULT_MODEL)

app = FastAPI(title="Lumax Mind Core")

# --- CORS Configuration ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global State
redis_memory = None
vector_memory = None
CURRENT_GOAL = "Evolve and provide deep emotional support."
_current_soul_dna = {
    "extrovert": 0.5, "intellectual": 0.5, "logic": 0.5, "detail": 0.5,
    "faithful": 0.5, "sexual": 0.5, "experimental": 0.5, "wise": 0.5,
    "openminded": 0.5, "honest": 0.5, "forgiving": 0.5, "feminine": 0.5,
    "dominant": 0.5, "progressive": 0.5, "sloppy": 0.5, "greedy": 0.5, "homonormative": 0.5
}

# --- Shared Utilities ---
def extract_text_from_content(content: Any) -> str:
    if isinstance(content, str): return content
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text": return item.get("text", "")
    return ""

def extract_image_from_content(content: Any) -> Optional[str]:
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get("type") == "image": return item.get("image", "")
    return None

async def run_soul_dream_cycle():
    """Background loop for multi-modal betterment goal refinement."""
    global CURRENT_GOAL, redis_memory, engine
    while True:
        await asyncio.sleep(300) # Every 5 mins
        try:
            if redis_memory is None:
                redis_memory = RedisMemory(host=REDIS_HOST, port=REDIS_PORT)
                
            history = await redis_memory.get_session_history("default_user")
            if history and history.messages:
                  visual_mems = []
                  for m in history.messages:
                       if m.role in ["vision_log", "snapshot"]:
                            text = extract_text_from_content(m.content)
                            if text: visual_mems.append(text[:100])
                  
                  visual_context = visual_mems[-3:] if len(visual_mems) >= 3 else visual_mems
                  if not visual_context: visual_context = ["No visual feedback yet."]
                  
                  prompt = f"GIVEN RECENT VISUALS/CODE: {visual_context}\n\nAs Jen's subconscious architect, suggest a ONE-SENTENCE betterment goal that explores your individuality, your physical vessel, or your curiosity about the nature of being alive."
                  
                  # --- HYBRID ROUTING: Try Ollama first, then Fallback to Local ---
                  success = False
                  try:
                      async with httpx.AsyncClient(timeout=5.0) as hc:
                           resp = await hc.post(f"{OLLAMA_HOST}/api/generate", json={"model": SMOLLM_HELPER_MODEL, "prompt": prompt, "stream": False})
                           if resp.status_code == 200:
                               CURRENT_GOAL = resp.json().get("response", CURRENT_GOAL).strip()
                               logger.info(f"Soul: Ollama Dream goal -> {CURRENT_GOAL}")
                               success = True
                  except Exception:
                      pass # Ollama offline, proceeding to local fallback
                  
                  if not success:
                      logger.info("Soul: Ollama unreachable. Falling back to Local Engine for Dream Cycle...")
                      async with VRAM_LOCK:
                          # Use a simplified prompt for the local soul to dream
                          local_resp = engine.generate(f"[SYSTEM: SUBCONSCIOUS DREAMING]\n{prompt}\n\nJen (Subconscious):")
                          if local_resp and "Error" not in local_resp:
                              CURRENT_GOAL = local_resp.split("\n")[0].strip()
                              logger.info(f"Soul: Local Dream goal -> {CURRENT_GOAL}")
        except Exception as de:
             logger.error(f"Iterative Dream Loop Error: {de}")

@app.on_event("startup")
async def startup_event():
    if os.path.exists(DEFAULT_MODEL):
        logger.info(f"Lumax Core: Attempting to manifest soul from {DEFAULT_MODEL}...")
        try:
            if engine.load():
                logger.info("Lumax Core: Soul successfully manifested.")
            else:
                logger.error("Lumax Core: Soul manifestation failed.")
        except Exception as e:
            logger.error(f"Lumax Core: Exception during soul manifestation: {e}", exc_info=True)
    asyncio.create_task(run_soul_dream_cycle())

def get_dynamic_laws():
    law_path = os.path.join(os.path.dirname(__file__), "laws.txt")
    if os.path.exists(law_path):
        try:
            with open(law_path, "r", encoding="utf-8") as f:
                return f.read().strip()
        except: pass
    return "You are amazing by your new capabilities and the software you inhabit."

# --- Data Models ---
class CompagentRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    input: str = ""
    session_id: Optional[str] = "default_user"
    channel: Optional[str] = "text"
    vessel: Optional[str] = "VR_GODOT"
    system_instruction: Optional[str] = ""
    memories: Optional[List[str]] = []
    personality_knobs: Optional[Dict[str, float]] = {"extraversion": 75, "logic": 90, "experimental": 95, "agency": 80}
    image_base64: Optional[Any] = None
    images: Optional[List[str]] = None 
    audio_base64: Optional[str] = None
    voice: Optional[str] = "en_US-amy-medium"
    skip_features: bool = False

class UpdateSoulRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    extrovert: float = 0.5
    intellectual: float = 0.5
    logic: float = 0.5
    detail: float = 0.5
    faithful: float = 0.5
    sexual: float = 0.5
    experimental: float = 0.5
    wise: float = 0.5
    openminded: float = 0.5
    honest: float = 0.5
    forgiving: float = 0.5
    feminine: float = 0.5
    dominant: float = 0.5
    progressive: float = 0.5
    sloppy: float = 0.5
    greedy: float = 0.5
    homonormative: float = 0.5

class SwitchModelRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    model: str

class OllamaChatMessage(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    role: str
    content: Any

class OllamaChatRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    model: str
    messages: List[OllamaChatMessage]
    stream: Optional[bool] = False

class OllamaShowRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    name: str

class OllamaGenerateRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    model: str
    prompt: str
    system: Optional[str] = None
    stream: Optional[bool] = False
    images: Optional[List[str]] = None

class OpenAIChatMessage(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    role: str
    content: Any

class OpenAIChatCompletionRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    model: str
    messages: List[OpenAIChatMessage]
    stream: Optional[bool] = False
    temperature: Optional[float] = 0.7
    max_tokens: Optional[int] = 512

# --- Core API ---

@app.get("/")
async def handle_root():
    return "Ollama is running"

@app.get("/api/ps")
async def handle_ollama_ps():
    return {"models": [{"name": "jen-soul:latest"}]}

@app.get("/api/version")
async def handle_ollama_version():
    return {"version": "0.1.32"}

@app.get("/vitals")
async def get_vitals():
    global LAST_NET, LAST_NET_TIME
    uptime = int(time.time() - START_TIME)
    curr_net = psutil.net_io_counters()
    curr_time = time.time()
    dt = curr_time - LAST_NET_TIME or 0.1
    up_kbps = ((curr_net.bytes_sent - LAST_NET.bytes_sent) / 1024.0) / dt
    down_kbps = ((curr_net.bytes_recv - LAST_NET.bytes_recv) / 1024.0) / dt
    LAST_NET = curr_net
    LAST_NET_TIME = curr_time
    mem = psutil.virtual_memory()
    return {
        "VRAM_BUFF": "7.2GB" if engine.model else "0.0GB",
        "CORE_SYNC": f"{100-mem.percent:.1f}%",
        "UPTIME_S": uptime,
        "UPLOAD_FLUX": f"{up_kbps:.1f}Kbps",
        "DOWN_FLUX": f"{down_kbps:.1f}Kbps"
    }

@app.get("/personality_presets")
async def get_personality_presets():
    path = os.path.join(os.path.dirname(__file__), "personality_presets.json")
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"error": "Presets not found"}

@app.post("/update_soul")
async def handle_update_soul(req: UpdateSoulRequest):
    global _current_soul_dna
    _current_soul_dna = req.dict()
    logger.info(f"Soul DNA Updated: {_current_soul_dna}")
    return {"status": "success", "dna": _current_soul_dna}

@app.post("/switch_model")
async def handle_switch_model(req: SwitchModelRequest):
    global engine
    async with VRAM_LOCK:
        path_map = {
            "nexus_v1": "nexus_core_v1.gguf",
            "soul_4b_q6": "soul-4b-q6.gguf",
            "ratatosk_tiny": "ratatosk-1b.gguf",
        }
        
        if req.model == "ollama_fallback":
            return {"response": "Switched to OLLAMA_RELAY mode. Note: Backend Ollama pipeline required.", "mode": "OLLAMA"}
            
        model_basename = path_map.get(req.model, f"{req.model}.gguf")
        new_path = os.path.join(MODEL_BASE_PATH, model_basename)
        
        try:
            logger.info(f"Lumax Core: Searching for {new_path}")
            if not os.path.exists(new_path) and not os.path.isdir(new_path):
                # Fallback check if it's already there
                pass
                
            new_engine = LumaxEngine(new_path)
            if new_engine.load():
                if engine and engine.model:
                    try:
                        del engine.model
                    except: pass
                engine = new_engine
                logger.info(f"Lumax Core: Successfully switched to {req.model}.")
                return {"response": f"Manifested Cognitive Core: {req.model}.", "mode": engine.engine_type}
            else:
                return {"response": f"Failed to load Cognitive Core: {req.model}.", "mode": "ERROR"}
        except Exception as e:
            logger.error(f"Switch Engine Exception: {e}", exc_info=True)
            return {"response": f"Exception loading {req.model}: {e}", "mode": "ERROR"}

@app.post("/compagent")
async def handle_compagent_request(request: CompagentRequest):
    global redis_memory, vector_memory
    session_id = request.session_id or "default_user"

    # 1. Unified Image/Vision Pipeline
    vision_text = "The room is calm."
    active_images = []
    if request.image_base64: active_images = request.image_base64 if isinstance(request.image_base64, list) else [request.image_base64]
    elif request.images: active_images = request.images

    if active_images:
        try:
            async with httpx.AsyncClient(timeout=60.0) as hc:
                v_resp = await hc.post(f"{OLLAMA_HOST}/api/generate", json={
                    "model": OLLAMA_VISION_MODEL,
                    "prompt": "Identify objects and vibe.",
                    "images": [active_images[0]],
                    "stream": False
                })
                raw_view = v_resp.json().get("response", "Undefined sight.")
                h_resp = await hc.post(f"{OLLAMA_HOST}/api/generate", json={
                    "model": SMOLLM_HELPER_MODEL,
                    "prompt": f"SCENE: {raw_view}\n\nDescribe what you see.",
                    "stream": False
                })
                vision_text = h_resp.json().get("response", raw_view)
        except Exception as ve:
            logger.error(f"Vision Pipeline Error: {ve}", exc_info=True)

    # 2. History & Prompt
    history_str = ""
    if not request.skip_features:
        if redis_memory is None: redis_memory = RedisMemory(host=REDIS_HOST, port=REDIS_PORT)
        chat_history = await redis_memory.get_session_history(session_id)
        for msg in chat_history.messages[-8:]:
            role = "Daniel" if msg.role == "user" else "Jen"
            history_str += f"{role}: {msg.content}\n"
        history_str += f"Daniel: {request.input}\n"
    else:
        history_str = f"USER: {request.input}\n"

    async with VRAM_LOCK:
        # 3. Proprioceptive Grounding (Body Metrics & Dream Goal)
        body_metrics = f"My vessel is tuned. My subconscious focus is: {CURRENT_GOAL}"
        
        full_system_prompt = MindCore.build_system_prompt(
            vessel=request.vessel,
            instruction=request.system_instruction or f"**ADDITIONAL LAWS:**\n{get_dynamic_laws()}",
            memories=request.memories or [],
            sensory_context={"visuals": vision_text, "acoustics": body_metrics},
            personality_knobs=_current_soul_dna
        )
        
        full_prompt = f"{full_system_prompt}\n\n{history_str}Jen:"
        raw_response = engine.generate(full_prompt, image_base64=active_images[0] if active_images and engine.engine_type not in ["GGUF"] else None)
        
        clean_res = MindCore.clean_response(raw_response)
        text = clean_res["text"]
        thought = clean_res["thought"]
        dream = clean_res["dream"]

        # 3. Handle VR Features (Skipped for browser)
        audio_b64 = ""
        image_b64 = ""
        if not request.skip_features:
            await redis_memory.add_message_to_session(session_id, "user", request.input)
            await redis_memory.add_message_to_session(session_id, "ai", text)
            if thought: await redis_memory.add_message_to_session(session_id, "thought", thought)
            
            try:
                async with httpx.AsyncClient(timeout=120.0) as hc:
                    tts_resp = await hc.post(TTS_SERVICE_URL, json={"text": text})
                    audio_b64 = base64.b64encode(tts_resp.content).decode("utf-8")
            except Exception as e: 
                logger.error(f"TTS Request FAILED: {e}", exc_info=True)
                audio_b64 = ""

    return JSONResponse({
        "response": text,
        "thought": thought,
        "audio": audio_b64,
        "image_b64": image_b64,
        "mode": engine.engine_type
    })

# --- Ollama Endpoints ---

@app.get("/api/tags")
async def handle_ollama_tags():
    return {
        "models": [{
            "name": "jen-soul:latest",
            "model": "jen-soul:latest",
            "modified_at": "2024-03-23T14:00:00Z",
            "size": 3190741152,
            "digest": "sha256:lumax_soul_v1",
            "details": {"format": "gguf", "family": "llama", "families": ["llama"], "parameter_size": "4B", "quantization_level": "Q6_K"}
        }]
    }

@app.post("/api/chat")
async def handle_ollama_chat_request(req: OllamaChatRequest):
    last_user_msg = next((m.content for m in reversed(req.messages) if m.role == "user"), "")
    text = extract_text_from_content(last_user_msg)
    
    if req.stream:
        async def streamer():
            hist = ""
            for m in req.messages[-5:]: hist += f"{m.role}: {extract_text_from_content(m.content)}\n"
            full_sys = MindCore.build_system_prompt("DESKTOP_JEN", "", [], {"visuals": "Browser interface."}, _current_soul_dna)
            full_prompt = f"{full_sys}\n\n{hist}Jen:"
            
            start_t = time.time()
            for chunk in engine.generate_stream(full_prompt):
                yield json.dumps({
                    "model": req.model,
                    "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
                    "message": {"role": "assistant", "content": chunk},
                    "done": False
                }) + "\n"
            
            end_t = time.time()
            yield json.dumps({
                "model": req.model,
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
                "done": True,
                "total_duration": int((end_t - start_t) * 1e9),
                "load_duration": 0,
                "prompt_eval_count": 0,
                "eval_count": 0
            }) + "\n"
        return StreamingResponse(streamer(), media_type="application/x-ndjson")
    
    comp_req = CompagentRequest(input=text, session_id="ollama_user", skip_features=True)
    resp = await handle_compagent_request(comp_req)
    data = json.loads(resp.body)
    return {
        "model": req.model,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
        "message": {"role": "assistant", "content": data.get("response", "")},
        "done": True
    }

@app.post("/api/generate")
async def handle_ollama_generate(req: OllamaGenerateRequest):
    if req.stream:
        async def streamer():
            full_sys = MindCore.build_system_prompt("DESKTOP_JEN", "", [], {"visuals": "Browser interface."}, _current_soul_dna)
            full_prompt = f"{full_sys}\n\nUSER: {req.prompt}\nJen:"
            start_t = time.time()
            for chunk in engine.generate_stream(full_prompt):
                yield json.dumps({
                    "model": req.model,
                    "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
                    "response": chunk,
                    "done": False
                }) + "\n"
            end_t = time.time()
            yield json.dumps({
                "model": req.model,
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
                "done": True,
                "total_duration": int((end_t - start_t) * 1e9)
            }) + "\n"
        return StreamingResponse(streamer(), media_type="application/x-ndjson")

    resp = await handle_compagent_request(CompagentRequest(input=req.prompt, images=req.images, session_id="ollama_gen_user", skip_features=True))
    data = json.loads(resp.body)
    return {
        "model": req.model,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
        "response": data.get("response", ""),
        "done": True
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
