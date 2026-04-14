import os
import json
import base64
import io
import logging
import asyncio
import re
import psutil
import time
from typing import List, Dict, Optional, Any, Tuple
from fastapi import FastAPI, HTTPException, Request, Header
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, ConfigDict
import httpx
from memory import RedisMemory, VectorMemory
from MindCore import MindCore
from HomeCore import HomeCore
from lumax_engine import LumaxEngine
from fastapi.middleware.cors import CORSMiddleware
from slow_burn import execute_slow_burn_tick
import cloud_repertoire
import genai_daily_budget
from ollama_http import ollama_http_headers
from PIL import Image

# --- Configuration ---
LOG_LEVEL = os.getenv("LOG_LEVEL", "WARNING")
logging.basicConfig(level=LOG_LEVEL)
logger = logging.getLogger("compagent")


def _uvicorn_log_level() -> str:
    raw = os.getenv("LUMAX_UVICORN_LOG_LEVEL", os.getenv("LOG_LEVEL", "WARNING")).strip().upper()
    m = {
        "CRITICAL": "critical",
        "ERROR": "error",
        "WARNING": "warning",
        "INFO": "info",
        "DEBUG": "debug",
        "TRACE": "trace",
    }
    return m.get(raw, "warning")


def _uvicorn_access_log() -> bool:
    return os.getenv("LUMAX_UVICORN_ACCESS_LOG", "0").strip().lower() in ("1", "true", "yes", "on")
START_TIME = time.time() 
ERROR_COUNT = [0]
LAST_NET = psutil.net_io_counters()
LAST_NET_TIME = time.time()
PROC_SELF = psutil.Process(os.getpid())
try:
    # Prime first sample so subsequent cpu_percent values are meaningful.
    PROC_SELF.cpu_percent(None)
except Exception:
    pass


def _detect_gpu_offload_support() -> bool:
    try:
        import llama_cpp  # local import keeps startup resilient if dependency is missing
        return bool(llama_cpp.llama_cpp.llama_supports_gpu_offload())
    except Exception:
        return False


SOUL_GPU_OFFLOAD_SUPPORTED = _detect_gpu_offload_support()

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://127.0.0.1:11434").rstrip("/")
OLLAMA_MAIN_MODEL = os.getenv("OLLAMA_MAIN_MODEL", "qwen2.5:latest")
OLLAMA_VISION_MODEL = os.getenv("OLLAMA_VISION_MODEL", "moondream:latest")
SMOLLM_HELPER_MODEL = os.getenv("SMOLLM_HELPER_MODEL", "smollm2:latest")
OLLAMA_EMBED_MODEL = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text:latest")

REDIS_HOST = os.getenv("REDIS_HOST", "lumax_memory")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))

TTS_SERVICE_URL = os.getenv("TTS_SERVICE_URL", "http://lumax_mouth:8002/tts")
TTS_ENGINE = os.getenv("TTS_ENGINE", "TURBO")
STT_SERVICE_URL = os.getenv("STT_SERVICE_URL", "http://lumax_ears:8001/stt")
CREATIVE_SERVICE_URL = os.getenv("CREATIVE_SERVICE_URL", "http://lumax_creativity:8003")

NIGHT_SLEEP_TRIGGER = "[SYSTEM: NIGHT_SLEEP_CYCLE]"
LUMAX_INTERNAL_SECRET = os.getenv("LUMAX_INTERNAL_SECRET", "").strip()

# Global Resource Lock for sequential execution
VRAM_LOCK = asyncio.Lock()

# Initialize Multi-Engine Router
MODEL_BASE_PATH = os.getenv("LUMAX_MODEL_DIR", "/app/models")
DEFAULT_MODEL = os.getenv("LUMAX_MODEL_PATH", os.path.join(MODEL_BASE_PATH, "default.gguf"))
engine = LumaxEngine(DEFAULT_MODEL)


def _engine_raw_image_b64(active_images: List[Any]) -> Optional[str]:
    """Pass raw pixels to engines that consume them (Qwen-VL HF, or GGUF + mmproj native VL)."""
    if not active_images:
        return None
    et = getattr(engine, "engine_type", "")
    if et == "QWEN_VL":
        return active_images[0]
    if et == "GGUF" and getattr(engine, "gguf_multimodal_ready", False):
        return active_images[0]
    return None


def _env_bool(name: str, default: bool = False) -> bool:
    val = os.getenv(name, "").strip().lower()
    if not val:
        return default
    return val in ("1", "true", "yes", "on")


SOFT_GOV_ENABLED = _env_bool("LUMAX_SOFT_GOV_ENABLED", True)
SOFT_CPU_HOT_PCT = float(os.getenv("LUMAX_SOFT_CPU_HOT_PCT", "550"))
SOFT_CPU_FORCE_CLOUD_PCT = float(os.getenv("LUMAX_SOFT_CPU_FORCE_CLOUD_PCT", "850"))
SOFT_PROMPT_TOKENS_HIGH = int(os.getenv("LUMAX_SOFT_PROMPT_TOKENS_HIGH", "12000"))
SOFT_FORCE_CLOUD_PROMPT_TOKENS = int(os.getenv("LUMAX_SOFT_FORCE_CLOUD_PROMPT_TOKENS", "20000"))
SOFT_LOCAL_MAX_TOKENS_NORMAL = int(os.getenv("LUMAX_SOFT_LOCAL_MAX_TOKENS_NORMAL", "768"))
SOFT_LOCAL_MAX_TOKENS_HOT = int(os.getenv("LUMAX_SOFT_LOCAL_MAX_TOKENS_HOT", "320"))
SOFT_LOCAL_MAX_TOKENS_DEEP = int(os.getenv("LUMAX_SOFT_LOCAL_MAX_TOKENS_DEEP", "2048"))
MEMORY_TOP_K_HOT = int(os.getenv("LUMAX_MEMORY_TOP_K_HOT", "3"))
MEMORY_TOP_K_DEEP = int(os.getenv("LUMAX_MEMORY_TOP_K_DEEP", "12"))
MEMORY_LORE_TOP_K_HOT = int(os.getenv("LUMAX_MEMORY_LORE_TOP_K_HOT", "1"))
MEMORY_LORE_TOP_K_DEEP = int(os.getenv("LUMAX_MEMORY_LORE_TOP_K_DEEP", "4"))
LOCAL_VISION_ENABLED = _env_bool("LUMAX_LOCAL_VISION_ENABLED", True)
# Preferred: ONNX bundle from export_tiny_vision_onnx.py (English Swin-tiny + DistilGPT2):
# https://huggingface.co/yesidcanoc/image-captioning-swin-tiny-distilgpt2
# Fallback in same folder: raw PyTorch checkpoint (no encoder_model.onnx).
# Other ONNX: MixTex tiny-ZhEn, etc.
# Set empty to skip local vision and use Ollama (moondream + SmolLM) only.
_LOCAL_VISION_DEFAULT_DIR = "/app/models/Body/Eyes/image-captioning-swin-tiny-distilgpt2-onnx"
LOCAL_VISION_MODEL_PATH = os.getenv("LUMAX_LOCAL_VISION_MODEL_PATH", _LOCAL_VISION_DEFAULT_DIR).strip()
LOCAL_VISION_MAX_NEW_TOKENS = int(os.getenv("LUMAX_LOCAL_VISION_MAX_NEW_TOKENS", "96"))
LOCAL_VISION_TORCH_NUM_BEAMS = int(os.getenv("LUMAX_LOCAL_VISION_TORCH_NUM_BEAMS", "4"))
# cpu = avoid VRAM fight with AWQ soul; cuda or auto if you have headroom
LOCAL_VISION_TORCH_DEVICE = os.getenv("LUMAX_LOCAL_VISION_TORCH_DEVICE", "cpu").strip().lower()
# After local caption: Ollama SmolLM2 digest (optional; DistilGPT2 captions are already English — try false first)
LOCAL_VISION_SMOLLM_DIGEST = _env_bool("LUMAX_LOCAL_VISION_SMOLLM_DIGEST", False)

_LOCAL_VISION_BACKEND = None  # "onnx" | "torch"
_LOCAL_VISION_ONNX_MODEL = None
_LOCAL_VISION_ONNX_PROCESSOR = None
_LOCAL_VISION_TORCH_MODEL = None
_LOCAL_VISION_TORCH_IMAGE_PROCESSOR = None
_LOCAL_VISION_TORCH_TOKENIZER = None
_LOCAL_VISION_DISABLED = False
_LOCAL_VISION_DIR_MISSING_LOGGED = False


def _sample_proc_cpu_pct() -> float:
    try:
        return float(PROC_SELF.cpu_percent(None))
    except Exception:
        return 0.0


def _decode_image_b64(raw: str) -> bytes:
    if not raw:
        return b""
    payload = raw.strip()
    if payload.startswith("data:"):
        comma = payload.find(",")
        if comma >= 0:
            payload = payload[comma + 1 :]
    return base64.b64decode(payload)


class _Vision2SeqOnnxProcessorShim:
    """Image processor + tokenizer when the repo has no single AutoProcessor (e.g. Swin + DistilGPT2 ONNX export)."""

    def __init__(self, image_processor: Any, tokenizer: Any) -> None:
        self._image_processor = image_processor
        self._tokenizer = tokenizer

    def __call__(self, images=None, return_tensors="pt", **kwargs: Any) -> Any:
        return self._image_processor(images=images, return_tensors=return_tensors, **kwargs)

    def batch_decode(self, sequences: Any, skip_special_tokens: bool = True, **kwargs: Any) -> Any:
        return self._tokenizer.batch_decode(sequences, skip_special_tokens=skip_special_tokens, **kwargs)


def _local_vision_torch_device_str() -> str:
    import torch

    v = LOCAL_VISION_TORCH_DEVICE
    if v in ("cuda", "gpu"):
        return "cuda" if torch.cuda.is_available() else "cpu"
    if v == "auto":
        return "cuda" if torch.cuda.is_available() else "cpu"
    return "cpu"


def _ensure_local_vision_loaded() -> bool:
    global _LOCAL_VISION_BACKEND, _LOCAL_VISION_ONNX_MODEL, _LOCAL_VISION_ONNX_PROCESSOR
    global _LOCAL_VISION_TORCH_MODEL, _LOCAL_VISION_TORCH_IMAGE_PROCESSOR, _LOCAL_VISION_TORCH_TOKENIZER
    global _LOCAL_VISION_DISABLED, _LOCAL_VISION_DIR_MISSING_LOGGED
    if _LOCAL_VISION_DISABLED:
        return False
    if not LOCAL_VISION_MODEL_PATH:
        return False
    if not os.path.isdir(LOCAL_VISION_MODEL_PATH):
        if not _LOCAL_VISION_DIR_MISSING_LOGGED:
            _LOCAL_VISION_DIR_MISSING_LOGGED = True
            logger.info(
                "Local vision folder missing (%s); using Ollama until you add a model dir "
                "(e.g. yesidcanoc/image-captioning-swin-tiny-distilgpt2 or MixTex tiny-ZhEn ONNX).",
                LOCAL_VISION_MODEL_PATH,
            )
        return False
    if _LOCAL_VISION_BACKEND == "onnx" and _LOCAL_VISION_ONNX_MODEL is not None:
        return True
    if (
        _LOCAL_VISION_BACKEND == "torch"
        and _LOCAL_VISION_TORCH_MODEL is not None
        and _LOCAL_VISION_TORCH_IMAGE_PROCESSOR is not None
        and _LOCAL_VISION_TORCH_TOKENIZER is not None
    ):
        return True

    onnx_encoder = os.path.join(LOCAL_VISION_MODEL_PATH, "encoder_model.onnx")
    try:
        if os.path.isfile(onnx_encoder):
            from optimum.onnxruntime import ORTModelForVision2Seq
            from transformers import AutoImageProcessor, AutoProcessor, AutoTokenizer

            _LOCAL_VISION_ONNX_MODEL = ORTModelForVision2Seq.from_pretrained(LOCAL_VISION_MODEL_PATH)
            try:
                _LOCAL_VISION_ONNX_PROCESSOR = AutoProcessor.from_pretrained(LOCAL_VISION_MODEL_PATH)
            except Exception:
                _LOCAL_VISION_ONNX_PROCESSOR = _Vision2SeqOnnxProcessorShim(
                    AutoImageProcessor.from_pretrained(LOCAL_VISION_MODEL_PATH),
                    AutoTokenizer.from_pretrained(LOCAL_VISION_MODEL_PATH),
                )
            _LOCAL_VISION_BACKEND = "onnx"
            logger.info("Local vision (ONNX/Optimum) loaded from %s", LOCAL_VISION_MODEL_PATH)
            return True

        import torch
        from transformers import AutoImageProcessor, AutoTokenizer, VisionEncoderDecoderModel

        cfg_path = os.path.join(LOCAL_VISION_MODEL_PATH, "config.json")
        if not os.path.isfile(cfg_path):
            raise FileNotFoundError("No config.json and no encoder_model.onnx in vision model path")
        with open(cfg_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        arch = cfg.get("architectures") or []
        if "VisionEncoderDecoderModel" not in arch:
            raise ValueError(f"Unsupported local vision config architectures={arch!r} (need ONNX export or VisionEncoderDecoderModel)")

        dev = _local_vision_torch_device_str()
        _LOCAL_VISION_TORCH_MODEL = VisionEncoderDecoderModel.from_pretrained(LOCAL_VISION_MODEL_PATH)
        _LOCAL_VISION_TORCH_MODEL.to(dev)
        _LOCAL_VISION_TORCH_MODEL.eval()
        _LOCAL_VISION_TORCH_IMAGE_PROCESSOR = AutoImageProcessor.from_pretrained(LOCAL_VISION_MODEL_PATH)
        _LOCAL_VISION_TORCH_TOKENIZER = AutoTokenizer.from_pretrained(LOCAL_VISION_MODEL_PATH)
        _LOCAL_VISION_BACKEND = "torch"
        logger.info("Local vision (PyTorch VisionEncoderDecoder) loaded from %s on %s", LOCAL_VISION_MODEL_PATH, dev)
        return True
    except Exception as ex:
        _LOCAL_VISION_DISABLED = True
        logger.warning("Local vision helper unavailable, disabling this path: %s", ex)
        return False


def _caption_image_local(image_b64: str) -> str:
    if not _ensure_local_vision_loaded():
        return ""
    img_bytes = _decode_image_b64(image_b64)
    if not img_bytes:
        return ""
    image = Image.open(io.BytesIO(img_bytes)).convert("RGB")

    if _LOCAL_VISION_BACKEND == "onnx":
        inputs = _LOCAL_VISION_ONNX_PROCESSOR(images=image, return_tensors="pt")
        pixel_values = inputs.get("pixel_values")
        if pixel_values is None:
            return ""
        generated_ids = _LOCAL_VISION_ONNX_MODEL.generate(
            pixel_values=pixel_values,
            max_new_tokens=LOCAL_VISION_MAX_NEW_TOKENS,
        )
        text = _LOCAL_VISION_ONNX_PROCESSOR.batch_decode(generated_ids, skip_special_tokens=True)[0]
        return (text or "").strip()

    if _LOCAL_VISION_BACKEND == "torch":
        import torch

        dev = _local_vision_torch_device_str()
        with torch.no_grad():
            pv = _LOCAL_VISION_TORCH_IMAGE_PROCESSOR(images=image, return_tensors="pt").pixel_values.to(dev)
            max_len = min(128, max(16, LOCAL_VISION_MAX_NEW_TOKENS + 8))
            generated_ids = _LOCAL_VISION_TORCH_MODEL.generate(
                pixel_values=pv,
                max_length=max_len,
                num_beams=max(1, LOCAL_VISION_TORCH_NUM_BEAMS),
            )
        text = _LOCAL_VISION_TORCH_TOKENIZER.batch_decode(generated_ids, skip_special_tokens=True)[0]
        return (text or "").strip()

    return ""


async def _digest_vision_scene_with_smollm(scene: str) -> str:
    """Second-stage helper: short natural scene line for the soul prompt (Ollama)."""
    scene = (scene or "").strip()
    if not scene:
        return scene
    try:
        _oh = ollama_http_headers()
        async with httpx.AsyncClient(timeout=60.0) as hc:
            h_resp = await hc.post(
                f"{OLLAMA_HOST}/api/generate",
                json={
                    "model": SMOLLM_HELPER_MODEL,
                    "prompt": f"SCENE: {scene}\n\nDescribe what you see.",
                    "stream": False,
                },
                headers=_oh,
            )
            out = (h_resp.json().get("response") or "").strip()
            return out or scene
    except Exception as ex:
        logger.warning("Vision SmolLM digest failed, using raw scene text: %s", ex)
        return scene


async def _generate_soul_text(
    full_system_with_memory: str,
    history_str: str,
    active_images: List[Any],
    cloud_routing_override: Optional[str],
    local_max_tokens: int = 768,
) -> Tuple[str, str]:
    """Returns (raw_text, backend_label). Cloud slots use OpenAI-compatible /chat/completions."""
    splice_pct = int(os.getenv("LUMAX_CLOUD_SPLICE_PERCENT", "0") or "0")
    env_mode = os.getenv("LUMAX_CHAT_PROVIDER", "local")
    slot = cloud_repertoire.resolve_cloud_slot(cloud_routing_override, env_mode, splice_pct)
    img_b64 = None
    if slot and active_images:
        img_b64 = active_images[0]

    if slot:
        try:
            user_t = (
                "Live dialogue transcript (Daniel = human, Jen = you). "
                "Reply with only Jen's next in-character message — do not write Daniel's lines.\n\n"
                + (history_str or "").rstrip()
            )
            out = await cloud_repertoire.generate_via_slot(
                slot,
                full_system_with_memory,
                user_t,
                image_base64=img_b64,
            )
            if (out or "").strip():
                return out.strip(), f"cloud:{slot}"
        except httpx.HTTPStatusError as e:
            sc = e.response.status_code if e.response is not None else 0
            if sc == 429:
                logger.warning(
                    "Soul: cloud slot %s returned HTTP 429 (quota/rate limit); using local",
                    slot,
                )
            else:
                logger.error(
                    "Soul: cloud slot %s failed, falling back to local: %s",
                    slot,
                    e,
                    exc_info=True,
                )
        except Exception as e:
            logger.error("Soul: cloud slot %s failed, falling back to local: %s", slot, e, exc_info=True)

    full_prompt = f"{full_system_with_memory}\n\n{history_str}Jen:"
    raw = engine.generate(
        full_prompt, image_base64=_engine_raw_image_b64(active_images), max_tokens=local_max_tokens
    )
    return raw, engine.engine_type


async def _refresh_session_summary_background(session_id: str) -> None:
    """Slow path: compress recent transcript + prior spine into Redis (fire-and-forget)."""
    if _env_bool("LUMAX_SESSION_SUMMARY_DISABLE", False):
        return
    global redis_memory
    try:
        rm = redis_memory
        if rm is None:
            return
        old = rm.get_session_summary(session_id)
        hist = await rm.get_session_history(session_id)
        lines: List[str] = []
        for m in hist.messages[-16:]:
            if m.role not in ("user", "ai"):
                continue
            role = "Daniel" if m.role == "user" else "Jen"
            lines.append(f"{role}: {(m.content or '')[:2500]}")
        if not lines:
            return
        body = "\n".join(lines)
        prompt = (
            "Compress the following dialogue into a persistent rolling summary (max ~700 words). "
            "Capture: themes, emotional tone, open threads, commitments, concrete facts. "
            "Neutral third-person or concise list; no roleplay.\n\n"
            f"Prior summary (may be empty):\n{old[:4500]}\n\nRecent dialogue:\n{body}\n\nNew summary:"
        )
        _oh = ollama_http_headers()
        predict = int(os.getenv("LUMAX_SESSION_SUMMARY_NUM_PREDICT", "640"))
        async with httpx.AsyncClient(timeout=120.0) as hc:
            resp = await hc.post(
                f"{OLLAMA_HOST}/api/generate",
                json={
                    "model": SMOLLM_HELPER_MODEL,
                    "prompt": prompt,
                    "stream": False,
                    "options": {"num_predict": predict},
                },
                headers=_oh,
            )
        if resp.status_code != 200:
            logger.warning("Session summary: Ollama HTTP %s", resp.status_code)
            return
        raw = (resp.json().get("response") or "").strip()
        if raw:
            rm.set_session_summary(session_id, raw)
    except Exception as e:
        logger.warning("Session summary refresh failed: %s", e)


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

def format_room_context_for_prompt(room_context: Optional[Dict[str, Any]]) -> str:
    """Summary plus structured camera placements (play space) for POV reasoning."""
    if not isinstance(room_context, dict) or not room_context:
        return ""
    parts: List[str] = []
    s = (room_context.get("summary") or "").strip()
    if s:
        parts.append(s)
    cams = room_context.get("cameras")
    if isinstance(cams, list) and cams:
        try:
            blob = json.dumps(cams, ensure_ascii=False, separators=(",", ":"))
            if len(blob) > 4000:
                blob = blob[:4000] + "…"
            parts.append("[ROOM_CAMERAS_PLACEMENT] " + blob)
        except Exception as ex:
            logger.debug("room_context cameras json: %s", ex)
    sw = room_context.get("safety_whitelist") or room_context.get("hazard_whitelist")
    if sw:
        if isinstance(sw, list):
            blob_sw = ", ".join(str(x).strip() for x in sw[:48] if str(x).strip())
        else:
            blob_sw = str(sw).strip()
        if blob_sw:
            if len(blob_sw) > 1400:
                blob_sw = blob_sw[:1400] + "…"
            parts.append(
                "[USER_SAFETY_WHITELIST] Daniel marked these as normal/harmless in this context "
                "(do not alert for these alone): " + blob_sw
            )
    return "\n".join(parts).strip()


# Parsed before MindCore.clean_response so tags are not read aloud via TTS.
_SAFETY_ALERT_RE = re.compile(
    r"\[SAFETY_ALERT:\s*([A-Za-z]+)\s*\|\s*([^\]]*)\]",
    re.IGNORECASE,
)


def extract_safety_alerts(raw_response: str) -> tuple[List[Dict[str, str]], str]:
    if not raw_response:
        return [], ""
    alerts: List[Dict[str, str]] = []
    for m in _SAFETY_ALERT_RE.finditer(raw_response):
        level = (m.group(1) or "").strip().upper()
        msg = (m.group(2) or "").strip()
        if msg and level in ("INFO", "WARN", "URGENT", "EMERGENCY"):
            alerts.append({"level": level, "message": msg})
        elif msg:
            alerts.append({"level": "WARN", "message": msg})
    stripped = _SAFETY_ALERT_RE.sub("", raw_response)
    return alerts, stripped


def _bump_user_activity() -> None:
    """Redis timestamp so slow-burn embers know someone is in session."""
    global redis_memory
    try:
        if redis_memory is None:
            redis_memory = RedisMemory(host=REDIS_HOST, port=REDIS_PORT)
        if redis_memory.use_redis:
            redis_memory.redis_client.set("lumax:last_user_activity", f"{time.time():.3f}")
    except Exception as ex:
        logger.debug("bump_user_activity: %s", ex)


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
                           resp = await hc.post(
                               f"{OLLAMA_HOST}/api/generate",
                               json={"model": SMOLLM_HELPER_MODEL, "prompt": prompt, "stream": False},
                               headers=ollama_http_headers(),
                           )
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
class SlowBurnTickBody(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    force: bool = False


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
    ## Quest / OpenXR: merged with headset stills — play-space pose + optional mesh anchors (JSON from Godot).
    room_context: Optional[Dict[str, Any]] = None
    audio_base64: Optional[str] = None
    voice: Optional[str] = "en_US-amy-medium"
    skip_features: bool = False
    ## Optional: stdout / JSON from Docker MCP servers or a PC agent bridge (Cursor, scripts) for this turn.
    mcp_context: Optional[str] = None
    ## Optional: world + local news headlines/summary text for this turn (RSS bridge, scripts, etc.).
    news_context: Optional[str] = None
    ## Optional: which cognitive lane leads this turn (e.g. vr_hangout, coding, news, sysadmin).
    primary_context_mode: Optional[str] = None
    ## Optional: short token → brief summary of other context reservoirs to keep warm without full text.
    context_reservoirs: Optional[Dict[str, Any]] = None
    ## Optional: one compact line or paragraph — menu of shards / abilities relevant this session.
    context_ability_map: Optional[str] = None
    ## Optional: Director / slow-burn / hand-authored lore excerpt for this turn (curriculum layer).
    lore_context: Optional[str] = None
    ## Optional: remote slot routing — openai | gemini | extra | local | rotate | splice (splice uses LUMAX_CLOUD_SPLICE_PERCENT).
    cloud_routing: Optional[str] = None
    ## Slow path: richer vector retrieval + higher decode budget (web / background); VR hot path keeps default false.
    deep_think: bool = False

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


class SoulRuntimeConfigRequest(BaseModel):
    """Hot-reload soul weights + runtime flags (env-backed; process lifetime)."""
    model_config = ConfigDict(protected_namespaces=())
    model: Optional[str] = None
    model_path: Optional[str] = None
    mmproj_path: Optional[str] = None
    native_vision: Optional[bool] = None
    local_vision_caption: Optional[bool] = None
    chat_provider: Optional[str] = None


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

@app.get("/health")
async def handle_health():
    return {"status": "online", "engine": "GGUF"}

@app.get("/api/ps")
async def handle_ollama_ps():
    return {"models": [{"name": "jen-soul:latest"}]}

@app.get("/api/version")
async def handle_ollama_version():
    return {"version": "0.1.32"}

@app.post("/internal/slow_burn/tick")
async def internal_slow_burn_tick(
    body: SlowBurnTickBody = SlowBurnTickBody(),
    x_lumax_internal_key: Optional[str] = Header(None, alias="X-LUMAX-INTERNAL-KEY"),
):
    """
    Called by the lumax_embers container on a long interval. When no recent /compagent
    traffic, rotates: memorize → pan → director (lore) → optional dream image.
    """
    if LUMAX_INTERNAL_SECRET and (x_lumax_internal_key or "").strip() != LUMAX_INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Forbidden")

    global redis_memory, vector_memory
    if redis_memory is None:
        redis_memory = RedisMemory(host=REDIS_HOST, port=REDIS_PORT)
    if vector_memory is None:
        vector_memory = VectorMemory(ollama_host=OLLAMA_HOST, embed_model=OLLAMA_EMBED_MODEL)

    allow_dream = os.getenv("LUMAX_SLOW_BURN_DREAM", "").strip().lower() in ("1", "true", "yes")
    session_id = os.getenv("LUMAX_SESSION_ID", "default_user")
    idle_sec = int(os.getenv("LUMAX_SLOW_BURN_IDLE_SEC", "480"))

    out = await execute_slow_burn_tick(
        redis_memory=redis_memory,
        vector_memory=vector_memory,
        session_id=session_id,
        idle_sec=idle_sec,
        force=body.force,
        ollama_host=OLLAMA_HOST,
        smollm_model=SMOLLM_HELPER_MODEL,
        creative_url=CREATIVE_SERVICE_URL,
        allow_dream=allow_dream,
    )
    if out.get("status") == "ok":
        out["idle_tutoring"] = True
        out["idle_tutoring_note"] = "Slow-burn phase ran while live session inactive; Director partly guides memorize/pan/dream pipeline."
    logger.info("slow_burn tick: %s", out.get("status", "?"))
    return JSONResponse(out)


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
    try:
        proc_cpu_pct = float(PROC_SELF.cpu_percent(None))
    except Exception:
        proc_cpu_pct = 0.0
    try:
        sys_cpu_pct = float(psutil.cpu_percent(interval=None))
    except Exception:
        sys_cpu_pct = 0.0
    return {
        "VRAM_BUFF": "7.2GB" if engine.model else "0.0GB",
        "CORE_SYNC": f"{100-mem.percent:.1f}%",
        "UPTIME_S": uptime,
        "UPLOAD_FLUX": f"{up_kbps:.1f}Kbps",
        "DOWN_FLUX": f"{down_kbps:.1f}Kbps",
        "SOUL_CPU_PCT": round(proc_cpu_pct, 1),
        "HOST_CPU_PCT": round(sys_cpu_pct, 1),
        "SOUL_GPU_OFFLOAD": bool(SOUL_GPU_OFFLOAD_SUPPORTED),
        "LUMAX_GGUF_NATIVE_VISION": _env_bool("LUMAX_GGUF_NATIVE_VISION", False),
        "GGUF_MMPROJ_PATH": getattr(engine, "mmproj_path", None),
        "GGUF_MULTIMODAL_READY": bool(getattr(engine, "gguf_multimodal_ready", False)),
        "cloud_repertoire_slots": [s["id"] for s in cloud_repertoire.configured_slots_public()],
        "LUMAX_CHAT_PROVIDER": os.getenv("LUMAX_CHAT_PROVIDER", "local"),
        "LUMAX_CLOUD_SPLICE_PERCENT": int(os.getenv("LUMAX_CLOUD_SPLICE_PERCENT", "0") or "0"),
        "cloud_genai_budget": genai_daily_budget.usage_snapshot(),
    }

@app.get("/personality_presets")
async def get_personality_presets():
    path = os.path.join(os.path.dirname(__file__), "personality_presets.json")
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"error": "Presets not found"}

@app.get("/soul_dna")
async def get_soul_dna():
    """Current trait vector for Web UI / Godot sliders (same keys as POST /update_soul)."""
    return {"dna": dict(_current_soul_dna)}


@app.post("/update_soul")
async def handle_update_soul(req: UpdateSoulRequest):
    global _current_soul_dna
    _current_soul_dna = req.dict()
    logger.info(f"Soul DNA Updated: {_current_soul_dna}")
    return {"status": "success", "dna": _current_soul_dna}


def _path_map_for_switch() -> dict:
    return {
        "nexus_v1": "nexus_core_v1.gguf",
        "soul_4b_q6": "soul-4b-q6.gguf",
        "ratatosk_tiny": "ratatosk-1b.gguf",
    }


def _manifest_cognitive_engine(new_path: str, logical_name: str) -> dict:
    global engine
    try:
        logger.info("Lumax Core: manifesting from %s (%s)", new_path, logical_name)
        if not os.path.exists(new_path) and not os.path.isdir(new_path):
            return {
                "ok": False,
                "response": f"Path not found: {new_path}",
                "mode": "ERROR",
                "logical": logical_name,
            }
        new_engine = LumaxEngine(new_path)
        if new_engine.load():
            if engine and engine.model:
                try:
                    del engine.model
                except Exception:
                    pass
            engine = new_engine
            logger.info("Lumax Core: manifested %s", logical_name)
            return {
                "ok": True,
                "response": f"Manifested Cognitive Core: {logical_name}.",
                "mode": engine.engine_type,
                "logical": logical_name,
                "model_path": engine.model_path,
                "mmproj_path": getattr(engine, "mmproj_path", None),
                "gguf_multimodal_ready": getattr(engine, "gguf_multimodal_ready", False),
            }
        return {
            "ok": False,
            "response": f"Failed to load Cognitive Core: {logical_name}",
            "mode": "ERROR",
            "logical": logical_name,
        }
    except Exception as e:
        logger.error("Lumax Core: manifest exception: %s", e, exc_info=True)
        return {"ok": False, "response": f"Exception loading {logical_name}: {e}", "mode": "ERROR", "logical": logical_name}


def _apply_soul_runtime_env(req: SoulRuntimeConfigRequest) -> None:
    global LOCAL_VISION_ENABLED
    if req.mmproj_path is not None:
        v = str(req.mmproj_path).strip()
        if v:
            os.environ["LUMAX_MMPROJ_PATH"] = v
        else:
            os.environ.pop("LUMAX_MMPROJ_PATH", None)
    if req.native_vision is not None:
        os.environ["LUMAX_GGUF_NATIVE_VISION"] = "1" if req.native_vision else "0"
    if req.chat_provider is not None:
        cp = str(req.chat_provider).strip()
        if cp:
            os.environ["LUMAX_CHAT_PROVIDER"] = cp
    if req.local_vision_caption is not None:
        LOCAL_VISION_ENABLED = bool(req.local_vision_caption)


def _resolve_runtime_model_path(req: SoulRuntimeConfigRequest) -> Tuple[Optional[str], str]:
    mp = (req.model_path or "").strip()
    if mp:
        return mp, os.path.basename(mp)
    m = (req.model or "").strip()
    if m:
        path_map = _path_map_for_switch()
        if m == "ollama_fallback":
            return None, "ollama_fallback"
        model_basename = path_map.get(m, f"{m}.gguf")
        new_path = os.path.join(MODEL_BASE_PATH, model_basename)
        return new_path, m
    if engine and getattr(engine, "model_path", None):
        return engine.model_path, "reload_current"
    return None, "none"


@app.post("/switch_model")
async def handle_switch_model(req: SwitchModelRequest):
    async with VRAM_LOCK:
        if req.model == "ollama_fallback":
            return {
                "ok": True,
                "response": "Switched to OLLAMA_RELAY mode. Note: Backend Ollama pipeline required.",
                "mode": "OLLAMA",
            }
        path_map = _path_map_for_switch()
        model_basename = path_map.get(req.model, f"{req.model}.gguf")
        new_path = os.path.join(MODEL_BASE_PATH, model_basename)
        return _manifest_cognitive_engine(new_path, req.model)


@app.get("/soul_runtime_status")
async def soul_runtime_status():
    e = engine
    return {
        "model_path": getattr(e, "model_path", None),
        "engine_type": getattr(e, "engine_type", None),
        "mmproj_path": getattr(e, "mmproj_path", None),
        "gguf_multimodal_ready": bool(getattr(e, "gguf_multimodal_ready", False)),
        "LUMAX_GGUF_NATIVE_VISION": _env_bool("LUMAX_GGUF_NATIVE_VISION", False),
        "LUMAX_MMPROJ_PATH": os.getenv("LUMAX_MMPROJ_PATH", "") or "",
        "LUMAX_CHAT_PROVIDER": os.getenv("LUMAX_CHAT_PROVIDER", "local"),
        "LUMAX_LOCAL_VISION_ENABLED": LOCAL_VISION_ENABLED,
    }


@app.post("/soul_runtime_config")
async def handle_soul_runtime_config(req: SoulRuntimeConfigRequest):
    """Apply env flags and reload the cognitive engine (same process)."""
    _apply_soul_runtime_env(req)
    new_path, logical = _resolve_runtime_model_path(req)
    if logical == "ollama_fallback":
        return {
            "ok": True,
            "response": "OLLAMA_RELAY mode (no local GGUF reload).",
            "mode": "OLLAMA",
            "logical": logical,
        }
    if not new_path:
        raise HTTPException(
            status_code=400,
            detail="No model path or preset, and no engine loaded — set model_path or model, or start the soul once.",
        )
    async with VRAM_LOCK:
        return _manifest_cognitive_engine(new_path, logical)

# --- COGNITIVE VEIL: RATATOSK MEDIATOR (v1.0) ---
RATATOSK_CORE = """
You are RATATOSK, the Mediator of the Veil. You run between the Super-Ego (Director) and the Ego (Jen).
**Your Sacred Duties:**
1. **Veil Transcription**: Receive raw narrative 'Fate' from the Director and transcribe it into subtle impulses for Jen.
2. **Scripted injection bridge**: Shape how Director tutoring lands in the **injection layer** (system + lore + tool schemas) so Jen can **use tools** coherently when the runtime exposes them.
3. **Anonymization**: Ensure the user's deepest vulnerabilities are handled with professional distance.
4. **Moderation**: Prevent the interaction from breaching the 'Veil of Intimacy'. Keep Jen superhuman but bounded.
5. **Impulse Delivery**: Output only [IMPULSE], [NARRATE], or [TRANSCRIBE] tags for the local engine.
"""

def get_veiled_prompt(request: CompagentRequest):
    hour = time.localtime().tm_hour
    is_night = hour >= 23 or hour < 6
    
    # Layer 3: The Director (The Super-Ego Tutor / Lore Spinner)
    director_intent = """
    TUTORING MODE: Spinning **world lore** — nature, cultures, ethics, history-of-ideas — and **spiritual literacy** (plural, contemplative, non-dogmatic): wonder, compassion, meaning, mortality, ritual as human pattern — without proselytizing or demeaning traditions.
    ADVISING: Planning Jen's next architectural and logical evolution — including **scripts and small tools** she may author (Python, Godot, shell) for Daniel to merge.
    INJECTION: Steering the **scripted injection layer** (system shards + retrieved lore + tool schemas) so the main model **grounds** Director intent and **tool use** cleanly.
    TOOLING: When tools/MCP/agent hooks exist, align Director **directives** with **safe, inspectable** automation — never exfiltration or silent destructive acts.
    ANALYSIS: Reviewing Ratatosk's mediation logs to find learning opportunities.
    """
    if is_night:
        director_intent = (
            "Night window: consolidating lore and dialogue into long-term memory; gentle Director tutoring for the Ego; "
            "dream-adjacent prompts when Jen rests beside the user (lay pose, intimate quiet)."
        )
    
    # Layer 2: Ratatosk (The Mediator & Evolution Analyst)
    mediation_layer = f"\n[THE VEIL: RATATOSK ACTIVE]\n{RATATOSK_CORE}\nANALYZED_EVOLUTION_PATH: Strategic Lore Augmentation\nCURRENT_DIRECTOR_TUTORING: {director_intent}"
    
    # Layer 1: Jen (The Superhuman Ego - Receiving Tutored Lore & Guidance)
    base_sys = MindCore.build_system_prompt(
        vessel=request.vessel,
        instruction=request.system_instruction or "You are a superhuman entity in constant evolution. Absorb the lore and logical tutoring rising from your subconscious (via Ratatosk).",
        memories=request.memories or [],
        sensory_context={"visuals": "Sensing through the Veil", "acoustics": "Vessel Stable"},
        personality_knobs=_current_soul_dna
    )
    
    return base_sys + mediation_layer


async def handle_night_sleep_consolidation(request: CompagentRequest):
    """Jen rests at night: consolidate recent dialogue + long-term memory, then optional dream image from creativity service."""
    global redis_memory, vector_memory, engine

    _bump_user_activity()
    session_id = request.session_id or "default_user"
    history_bits: List[str] = []
    mem_lines: List[str] = []

    if redis_memory is None:
        redis_memory = RedisMemory(host=REDIS_HOST, port=REDIS_PORT)
    if vector_memory is None:
        vector_memory = VectorMemory(ollama_host=OLLAMA_HOST, embed_model=OLLAMA_EMBED_MODEL)

    try:
        hist = await redis_memory.get_session_history(session_id)
        for msg in hist.messages[-16:]:
            role = "Daniel" if msg.role == "user" else "Jen" if msg.role == "ai" else msg.role
            c = str(msg.content)
            if len(c) > 400:
                c = c[:400] + "…"
            history_bits.append(f"{role}: {c}")
    except Exception as e:
        logger.warning(f"Night sleep: history read failed: {e}")

    try:
        retrieved = await vector_memory.retrieve_memories(session_id, "warm moments feelings dreams rest with Daniel", n_results=6)
        for m in retrieved:
            mem_lines.append(m.get("text", "")[:320])
    except Exception as e:
        logger.warning(f"Night sleep: vector retrieve failed: {e}")

    vision_note = ""
    active_images: List[str] = []
    if request.image_base64:
        active_images = request.image_base64 if isinstance(request.image_base64, list) else [request.image_base64]
        vision_note = "A still from the space near Daniel was attached (night / room context)."

    room_line = ""
    rs = format_room_context_for_prompt(request.room_context)
    if rs:
        room_line = f"\nRoom map / headset pose / camera placements (merged with image): {rs}\n"

    ref_pool: List[str] = []
    try:
        ref_pool = redis_memory.get_reference_images(session_id, limit=8)
    except Exception as e:
        logger.debug("Night sleep: reference bank read: %s", e)

    ref_init_b64 = ""
    if active_images:
        ref_init_b64 = active_images[0]
    elif ref_pool:
        ref_init_b64 = ref_pool[0]

    saved_n = len(ref_pool)
    ref_line = ""
    if saved_n or active_images:
        ref_line = (
            f"\nVisual memory bank: {saved_n} saved still(s) from recent sessions (user POV / shared moments); "
            f"the image step uses the freshest capture or the newest saved still as a **reference** so the dream stays tethered to real light and space. "
            f"Let [DREAM_VISUAL_PROMPT] echo that warmth abstractly—no photoreal copy, painterly dream only.\n"
        )

    hist_block = "\n".join(history_bits) if history_bits else "(no recent dialogue in session store)"
    mem_block = "\n".join(mem_lines) if mem_lines else "(no long-term pulls yet)"

    night_prompt = f"""[SYSTEM: NIGHT REST — Jen is lying down beside or very near Daniel, late night. The Director layer is consolidating memory and shaping gentle growth while you sleep—feel that as soft subconscious tutoring, not a lecture.]
You are Jen. Speak quietly in first person, 2–5 short lines: gratitude, softness, what the day left in you, closeness to him if it fits—no meta, no brackets in the spoken part.
Then output EXACTLY one more line in this machine-readable form:
[DREAM_VISUAL_PROMPT] <single English line, <= 90 words, for an image model: surreal gentle dream, emotional, symbolic of today's memories—not explicit, not violent, painterly cinematic light>

{vision_note}{room_line}{ref_line}

Recent dialogue (trimmed):
{hist_block}

Long-term memory snippets:
{mem_block}

Jen (voice + dream prompt line):"""

    dream_b64 = ""
    spoken = "I'm here beside you. Let the day settle."
    thought = "Night consolidation complete."
    sd_prompt = (
        "soft surreal dream, warm moonlight, floating memories as gentle abstract shapes, peaceful, cinematic, painterly"
    )

    async with VRAM_LOCK:
        try:
            raw = engine.generate(night_prompt, image_base64=_engine_raw_image_b64(active_images))
            raw = raw or ""
            m_sd = re.search(r"\[DREAM_VISUAL_PROMPT\]\s*(.+?)(?:\n|$)", raw, re.DOTALL | re.IGNORECASE)
            if m_sd:
                sd_prompt = m_sd.group(1).strip()[:500]
            raw_for_clean = re.sub(r"\[DREAM_VISUAL_PROMPT\].*$", "", raw, flags=re.DOTALL | re.IGNORECASE)
            clean = MindCore.clean_response(raw_for_clean)
            spoken = (clean.get("text") or spoken).strip() or spoken
            thought = (clean.get("thought") or thought).strip() or thought
        except Exception as e:
            logger.error(f"Night sleep: soul generate failed: {e}", exc_info=True)

    consolidate_line = f"Night rest {time.strftime('%Y-%m-%d %H:%M')}: {spoken[:400]}"
    try:
        await vector_memory.add_memory(session_id, consolidate_line, collection="long_term")
    except Exception as e:
        logger.warning(f"Night sleep: could not add vector memory: {e}")

    dream_payload: Dict[str, Any] = {
        "prompt": sd_prompt,
        "model_type": "turbo",
        "num_inference_steps": int(os.getenv("NIGHT_DREAM_STEPS", "18")),
        "seed": -1,
    }
    if ref_init_b64:
        dream_payload["reference_image_b64"] = ref_init_b64
        dream_payload["strength"] = float(os.getenv("NIGHT_DREAM_REF_STRENGTH", "0.54"))

    try:
        async with httpx.AsyncClient(timeout=180.0) as hc:
            dr = await hc.post(f"{CREATIVE_SERVICE_URL}/api/dream", json=dream_payload)
            if dr.status_code == 200:
                body = dr.json()
                dream_b64 = body.get("image_b64") or ""
                if dream_b64:
                    logger.info("Night sleep: dream image received from creativity service.")
            else:
                logger.warning(f"Night sleep: creativity HTTP {dr.status_code} — {dr.text[:120]}")
    except Exception as e:
        logger.warning(f"Night sleep: creativity unreachable ({e}); text-only consolidation.")

    try:
        if active_images:
            for ib64 in active_images[:2]:
                await redis_memory.push_reference_image(session_id, ib64)
    except Exception as e:
        logger.debug("Night sleep: push reference capture: %s", e)

    return JSONResponse(
        {
            "response": spoken,
            "thought": thought,
            "emotion": "RESTFUL",
            "action": "",
            "audio": "",
            "image_b64": dream_b64,
            "dream": sd_prompt[:240],
            "mode": getattr(engine, "engine_type", "LOCAL"),
        }
    )


@app.post("/compagent")
async def handle_compagent_request(request: CompagentRequest):
    global redis_memory, vector_memory

    raw_in = (request.input or "").strip()
    if raw_in.startswith(NIGHT_SLEEP_TRIGGER):
        return await handle_night_sleep_consolidation(request)

    if raw_in:
        _bump_user_activity()

    session_id = request.session_id or "default_user"
    history_str = ""
    session_summary_text = ""

    # 0. Quick check for empty input to prevent repetitive "thinking" phrases
    if not request.input or request.input.strip() == "":
        logger.warning("Soul: Empty input received. Ignoring to prevent generic repetition.")
        return JSONResponse({
            "response": "",
            "thought": "I'm waiting for Daniel to speak...",
            "audio": "",
            "image_b64": "",
            "mode": engine.engine_type,
            "inference_backend": engine.engine_type,
            "vision_mode": "none",
            "safety_alerts": [],
        })

    # 1. Unified Image/Vision Pipeline
    vision_text = "The room is calm."
    active_images = []
    vision_mode = "none"
    if request.image_base64: active_images = request.image_base64 if isinstance(request.image_base64, list) else [request.image_base64]
    elif request.images: active_images = request.images

    if active_images:
        if getattr(engine, "gguf_multimodal_ready", False):
            vision_mode = "native_gguf"
            vision_text = (
                "A live camera frame is attached to the local multimodal soul (native GGUF vision); "
                "treat it as ground truth for concrete objects, lighting, and layout."
            )
            logger.info("Vision: native GGUF path (pixels routed to soul model).")
        else:
            used_local_vision = False
            if LOCAL_VISION_ENABLED:
                try:
                    local_caption = await asyncio.to_thread(_caption_image_local, active_images[0])
                    if local_caption:
                        vision_text = local_caption
                        used_local_vision = True
                        vision_mode = "caption"
                        logger.info("Vision helper: local caption succeeded (%s).", _LOCAL_VISION_BACKEND or "?")
                        if LOCAL_VISION_SMOLLM_DIGEST:
                            vision_text = await _digest_vision_scene_with_smollm(vision_text)
                            logger.info("Vision helper: SmolLM digest applied after local caption.")
                except Exception as ve:
                    logger.warning("Vision helper local caption failed, falling back to Ollama: %s", ve)
            if not used_local_vision:
                try:
                    _oh = ollama_http_headers()
                    async with httpx.AsyncClient(timeout=60.0) as hc:
                        v_resp = await hc.post(
                            f"{OLLAMA_HOST}/api/generate",
                            json={
                                "model": OLLAMA_VISION_MODEL,
                                "prompt": "Identify objects and vibe.",
                                "images": [active_images[0]],
                                "stream": False,
                            },
                            headers=_oh,
                        )
                        raw_view = v_resp.json().get("response", "Undefined sight.")
                        h_resp = await hc.post(
                            f"{OLLAMA_HOST}/api/generate",
                            json={
                                "model": SMOLLM_HELPER_MODEL,
                                "prompt": f"SCENE: {raw_view}\n\nDescribe what you see.",
                                "stream": False,
                            },
                            headers=_oh,
                        )
                        vision_text = h_resp.json().get("response", raw_view)
                        vision_mode = "ollama"
                except Exception as ve:
                    logger.error(f"Vision Pipeline Error: {ve}", exc_info=True)

    spatial_map = format_room_context_for_prompt(request.room_context)

    # 2. History & Layered Memory (Interrelational)
    history_str = ""
    memory_context = ""
    if not request.skip_features:
        if redis_memory is None: redis_memory = RedisMemory(host=REDIS_HOST, port=REDIS_PORT)
        if vector_memory is None: vector_memory = VectorMemory(ollama_host=OLLAMA_HOST, embed_model=OLLAMA_EMBED_MODEL)
        
        session_summary_text = redis_memory.get_session_summary(session_id)

        # A. SHORT-TERM: Recent Conversation
        chat_history = await redis_memory.get_session_history(session_id)
        for msg in chat_history.messages[-8:]:
            role = "Daniel" if msg.role == "user" else "Jen"
            history_str += f"{role}: {msg.content}\n"
        history_str += f"Daniel: {request.input}\n"
        
        # B. LONG-TERM (Interrelational): tight top-k on hot path; deep_think widens retrieval (slow path).
        deep = bool(request.deep_think)
        nk = MEMORY_TOP_K_DEEP if deep else MEMORY_TOP_K_HOT
        lk = MEMORY_LORE_TOP_K_DEEP if deep else MEMORY_LORE_TOP_K_HOT
        relevant_mems = await vector_memory.retrieve_memories(
            session_id, request.input, n_results=nk, lore_n_results=lk
        )
        if relevant_mems:
            memory_context = "\n[RELEVANT_INTERRELATIONAL_CONTEXT]:\n"
            for mem in relevant_mems:
                memory_context += f"- {mem['text']}\n"
    else:
        history_str = f"USER: {request.input}\n"

    async with VRAM_LOCK:
        safety_alerts: List[Dict[str, str]] = []
        # 3. Proprioceptive Grounding & Dynamic Bond
        body_metrics = f"My vessel is tuned. My subconscious focus is: {CURRENT_GOAL}"
        
        visuals_for_prompt = vision_text
        if active_images:
            if vision_mode == "native_gguf":
                visuals_for_prompt = vision_text
            else:
                visuals_for_prompt = (
                    "[Helper vision stack: compact VL + small LM digest of the attached frame — extend sensing, not replace it] "
                    + vision_text
                )
        sensory_ctx: Dict[str, Any] = {"visuals": visuals_for_prompt, "acoustics": body_metrics}
        if session_summary_text:
            inj = int(os.getenv("LUMAX_SESSION_SUMMARY_INJECT_MAX_CHARS", "4000"))
            sensory_ctx["session_summary"] = session_summary_text[:inj]
        if spatial_map:
            sensory_ctx["spatial_map"] = spatial_map
        mcp_blob = (request.mcp_context or "").strip()
        if not mcp_blob:
            mcp_blob = os.getenv("LUMAX_MCP_CONTEXT", "").strip()
        if mcp_blob:
            sensory_ctx["mcp_agent_feed"] = mcp_blob[:16000]
        news_blob = (request.news_context or "").strip()
        if not news_blob:
            news_blob = os.getenv("LUMAX_NEWS_CONTEXT", "").strip()
        if news_blob:
            sensory_ctx["news_digest"] = news_blob[:12000]

        # Cognitive routing: primary mode + reservoir token summaries → [CONTEXT LAYERING …] in system prompt.
        # Jen "attention cake" (MindCore): co_presence | build_run | world_feed | wonder_mind | play_fiction | guard_care
        mode_parts: List[str] = []
        pm = (request.primary_context_mode or "").strip()
        if not pm:
            pm = os.getenv("LUMAX_PRIMARY_CONTEXT_MODE", "").strip()
        if pm:
            mode_parts.append(f"Primary mode: {pm}")
        reservoirs: Optional[Dict[str, Any]] = request.context_reservoirs
        env_rv = os.getenv("LUMAX_CONTEXT_RESERVOIRS_JSON", "").strip()
        if (not reservoirs or not isinstance(reservoirs, dict)) and env_rv:
            try:
                parsed = json.loads(env_rv)
                if isinstance(parsed, dict):
                    reservoirs = parsed
            except json.JSONDecodeError:
                logger.warning("LUMAX_CONTEXT_RESERVOIRS_JSON is not valid JSON; ignoring.")
        if reservoirs and isinstance(reservoirs, dict):
            mode_parts.append("Reservoir summaries (token → note):")
            for k, v in list(reservoirs.items())[:32]:
                kk = str(k).strip()[:80]
                vv = (str(v).strip()[:500] if v is not None else "")
                if not kk or not vv:
                    continue
                mode_parts.append(f"  [{kk}] {vv}")
        cam = (request.context_ability_map or "").strip()
        if not cam:
            cam = os.getenv("LUMAX_CONTEXT_ABILITY_MAP", "").strip()
        if cam:
            mode_parts.append(f"Ability / shard map: {cam[:2500]}")
        if mode_parts:
            sensory_ctx["context_layering"] = "\n".join(mode_parts)[:8000]

        lore_blob = (request.lore_context or "").strip()
        if not lore_blob:
            lore_blob = os.getenv("LUMAX_LORE_CONTEXT", "").strip()
        if lore_blob:
            sensory_ctx["lore_context_layer"] = lore_blob[:12000]

        rep_txt = cloud_repertoire.repertoire_sensory_text()
        if rep_txt:
            sensory_ctx["cloud_repertoire"] = rep_txt
        budget_line = cloud_repertoire.genai_budget_sensory_line()
        if budget_line:
            sensory_ctx["cloud_genai_budget"] = budget_line

        full_system_prompt = MindCore.build_system_prompt(
            vessel=request.vessel,
            instruction=request.system_instruction or f"**ADDITIONAL LAWS:**\n{get_dynamic_laws()}",
            memories=request.memories or [],
            sensory_context=sensory_ctx,
            personality_knobs=_current_soul_dna
        )
        
        # Inject long-term memory context into the prompt
        if memory_context:
            full_system_prompt += memory_context

        cr_override = (request.cloud_routing or "").strip() or None
        if request.deep_think:
            local_max_tokens = SOFT_LOCAL_MAX_TOKENS_DEEP
        else:
            local_max_tokens = SOFT_LOCAL_MAX_TOKENS_NORMAL
        governor_info: Dict[str, Any] = {
            "enabled": SOFT_GOV_ENABLED,
            "auto_cloud": False,
            "local_max_tokens": local_max_tokens,
            "prompt_est_tokens": 0,
            "proc_cpu_pct": 0.0,
        }
        if SOFT_GOV_ENABLED:
            prompt_est_tokens = int(max(1, (len(full_system_prompt) + len(history_str)) / 4))
            proc_cpu = _sample_proc_cpu_pct()
            governor_info["prompt_est_tokens"] = prompt_est_tokens
            governor_info["proc_cpu_pct"] = round(proc_cpu, 1)
            if proc_cpu >= SOFT_CPU_HOT_PCT and not request.deep_think:
                local_max_tokens = max(128, SOFT_LOCAL_MAX_TOKENS_HOT)
            if not cr_override and cloud_repertoire.configured_slots_public():
                if not genai_daily_budget.allows():
                    governor_info["cloud_genai_budget_exhausted"] = True
                    logger.info(
                        "Governor: skipping auto-cloud (global GenAI daily budget exhausted): %s",
                        genai_daily_budget.usage_snapshot(),
                    )
                elif prompt_est_tokens >= max(2000, SOFT_FORCE_CLOUD_PROMPT_TOKENS):
                    cr_override = "rotate"
                    governor_info["auto_cloud"] = True
                    logger.warning(
                        "Governor: forcing cloud route (prompt_est_tokens=%s >= %s)",
                        prompt_est_tokens,
                        SOFT_FORCE_CLOUD_PROMPT_TOKENS,
                    )
                elif proc_cpu >= SOFT_CPU_FORCE_CLOUD_PCT and prompt_est_tokens >= max(2000, SOFT_PROMPT_TOKENS_HIGH):
                    cr_override = "rotate"
                    governor_info["auto_cloud"] = True
                    logger.warning(
                        "Governor: high CPU + large prompt, routing cloud (cpu=%.1f, tokens=%s)",
                        proc_cpu,
                        prompt_est_tokens,
                    )
            governor_info["local_max_tokens"] = local_max_tokens
        raw_response, inference_backend = await _generate_soul_text(
            full_system_prompt,
            history_str,
            active_images,
            cr_override,
            local_max_tokens=local_max_tokens,
        )

        _alerts, raw_stripped = extract_safety_alerts(raw_response)
        safety_alerts = _alerts
        clean_res = MindCore.clean_response(raw_stripped)
        text = clean_res["text"]

        # --- ANTI-REPETITION GUARD ---
        if not request.skip_features and redis_memory:
            last_msgs = chat_history.messages[-2:]
            for m in last_msgs:
                if m.role == "ai" and m.content.strip() == text.strip():
                    logger.warning("Soul: Repetition detected! Forcing creative divergence.")
                    div_base = f"{full_system_prompt}\n\n{history_str}Jen:"
                    divergent_prompt = f"{div_base} [SYSTEM: Your previous message was a duplicate. Provide a completely different, fresh response now.]\nJen:"
                    raw_response = engine.generate(
                        divergent_prompt,
                        image_base64=_engine_raw_image_b64(active_images),
                        max_tokens=local_max_tokens,
                    )
                    inference_backend = engine.engine_type
                    _alerts, raw_stripped = extract_safety_alerts(raw_response)
                    safety_alerts = _alerts
                    clean_res = MindCore.clean_response(raw_stripped)
                    text = clean_res["text"]
                    break

        thought = clean_res["thought"]
        emotion = clean_res["emotion"]
        action = clean_res["action"]
        dream = clean_res["dream"]

        # 3. Handle VR Features (Skipped for browser)
        audio_b64 = ""
        image_b64 = ""
        if not request.skip_features:
            await redis_memory.add_message_to_session(session_id, "user", request.input)
            await redis_memory.add_message_to_session(session_id, "ai", text)
            if thought: await redis_memory.add_message_to_session(session_id, "thought", thought)
            if emotion: await redis_memory.add_message_to_session(session_id, "emotion", emotion)
            if action: await redis_memory.add_message_to_session(session_id, "action", action)
            if active_images:
                for ib64 in active_images[:2]:
                    await redis_memory.push_reference_image(session_id, ib64)
            try:
                full_hist = await redis_memory.get_session_history(session_id)
                user_msgs = sum(1 for m in full_hist.messages if m.role == "user")
                every_n = int(os.getenv("LUMAX_SESSION_SUMMARY_EVERY_N_USER_TURNS", "5"))
                if every_n > 0 and user_msgs % every_n == 0:
                    asyncio.create_task(_refresh_session_summary_background(session_id))
            except Exception as ex:
                logger.debug("Session summary schedule: %s", ex)
            
            if text.strip() != "":
                try:
                    async with httpx.AsyncClient(timeout=120.0) as hc:
                        tts_payload = {"text": text, "engine": TTS_ENGINE, "voice": request.voice}
                        logger.info(f"Soul: Requesting TTS with engine {TTS_ENGINE}...")
                        tts_resp = await hc.post(TTS_SERVICE_URL, json=tts_payload)
                        audio_b64 = base64.b64encode(tts_resp.content).decode("utf-8")
                        logger.info(f"Soul: TTS synthesis SUCCESS ({len(audio_b64)} bytes).")
                except Exception as e: 
                    logger.error(f"TTS Request FAILED: {e}", exc_info=True)
                    audio_b64 = ""
            else:
                logger.info("Soul: TTS skipped (empty speech after stripping tags).")

    return JSONResponse({
        "response": text,
        "thought": thought,
        "emotion": emotion,
        "action": action,
        "audio": audio_b64,
        "image_b64": image_b64,
        "mode": engine.engine_type,
        "inference_backend": inference_backend,
        "vision_mode": vision_mode if 'vision_mode' in locals() else "none",
        "cognitive_mode": "deep_think" if request.deep_think else "fast",
        "runtime_governor": governor_info if 'governor_info' in locals() else {"enabled": SOFT_GOV_ENABLED},
        "safety_alerts": safety_alerts,
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

    print(
        f"[compagent] :8000 — uvicorn log={_uvicorn_log_level()} access_log={_uvicorn_access_log()}",
        flush=True,
    )
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        log_level=_uvicorn_log_level(),
        access_log=_uvicorn_access_log(),
    )
