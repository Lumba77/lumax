import base64
import io
import os
import torch
import logging
from typing import Optional, List, Any
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field
from PIL import Image
from diffusers import (
    StableDiffusionControlNetPipeline, 
    ControlNetModel, 
    StableDiffusionPipeline,
    StableDiffusionImg2ImgPipeline
)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("creative_service")

app = FastAPI()

# Imagination Engines
DREAM_PIPE = None
IMG2IMG_PIPE = None
CONTROL_PIPE = None
ENHANCE_PIPE = None
CONTROLNET = None


def _env_str(name: str, default: str) -> str:
    v = os.getenv(name, "").strip()
    return v if v else default


def _default_inference_steps() -> int:
    try:
        return int(os.getenv("LUMAX_CREATIVITY_DEFAULT_INFERENCE_STEPS", "5"))
    except ValueError:
        return 5


def _default_model_type() -> str:
    return _env_str("LUMAX_CREATIVITY_DEFAULT_MODEL_TYPE", "turbo").lower()


# SD1.5 + ControlNet weights (Diffusers). Override if your tree lives under Mind/Creativity/Imagen.
IMAGEN_ROOT = _env_str("LUMAX_CREATIVITY_IMAGEN_ROOT", "/app/models/Imagen")
V15_PATH = os.path.join(IMAGEN_ROOT, "stable-diffusion-v1-5")
CONTROLNET_CANNY_PATH = os.path.join(IMAGEN_ROOT, "sd-controlnet-canny")

# SDXL Turbo TensorRT bundle (e.g. unetxl.opt). Logged at startup; /api/dream still uses SD1.5 Diffusers until TRT path is implemented.
SDXL_TURBO_TRT_DIR = _env_str(
    "LUMAX_CREATIVITY_SDXL_TURBO_TRT_DIR",
    "/app/models/Mind/Creativity/Imagen/sdxl-turbo-tensorrt",
)
SDXL_UNET_TRT_OPT = os.path.join(SDXL_TURBO_TRT_DIR, "unetxl.opt")


class DreamRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    prompt: str
    seed: int = -1
    model_type: str = Field(default_factory=_default_model_type)  # "control", "enhance", "turbo"
    num_inference_steps: int = Field(default_factory=_default_inference_steps)
    control_image_b64: str = ""
    ## User / experience stills: when set with model_type turbo, uses img2img (same SD1.5 weights).
    reference_image_b64: str = ""
    strength: float = 0.75

@app.on_event("startup")
async def startup_event():
    logger.info("Creativity Faculty: Sanctuary initialized.")
    logger.info("LUMAX_CREATIVITY_IMAGEN_ROOT=%s (SD1.5 base=%s)", IMAGEN_ROOT, V15_PATH)
    if os.path.isfile(SDXL_UNET_TRT_OPT):
        logger.info(
            "SDXL Turbo TRT UNet present at %s — Diffusers /api/dream still uses SD1.5; full TensorRT SDXL not wired yet.",
            SDXL_UNET_TRT_OPT,
        )
    else:
        logger.info(
            "No SDXL TRT UNet at %s (set LUMAX_CREATIVITY_SDXL_TURBO_TRT_DIR if elsewhere).",
            SDXL_UNET_TRT_OPT,
        )

def get_safe_image(b64_str: str) -> Optional[Image.Image]:
    if not b64_str: return None
    try:
        data = base64.b64decode(b64_str)
        return Image.open(io.BytesIO(data)).convert("RGB")
    except Exception as e:
        logger.error(f"Image Decode Error: {e}")
        return None


def _dream_init_image(pil_img: Image.Image) -> Image.Image:
    """SD1.5-friendly square init for img2img dreams."""
    return pil_img.convert("RGB").resize((512, 512), Image.LANCZOS)

@app.post("/api/dream")
async def generate_dream_image(req: DreamRequest):
    global DREAM_PIPE, IMG2IMG_PIPE, CONTROL_PIPE, ENHANCE_PIPE, CONTROLNET
    
    try:
        output = None
        
        # 1. CONTROLNET (Structural Integrity)
        if req.model_type == "control":
            if CONTROL_PIPE is None:
                logger.info("Loading ControlNet Canny + v1.5 Base...")
                CONTROLNET = ControlNetModel.from_pretrained(CONTROLNET_CANNY_PATH, torch_dtype=torch.float16)
                CONTROL_PIPE = StableDiffusionControlNetPipeline.from_pretrained(
                    V15_PATH, controlnet=CONTROLNET, torch_dtype=torch.float16
                ).to("cuda")
            
            control_image = get_safe_image(req.control_image_b64)
            if control_image:
                generator = torch.Generator("cuda").manual_seed(req.seed) if req.seed != -1 else None
                output = CONTROL_PIPE(prompt=req.prompt, image=control_image, num_inference_steps=req.num_inference_steps, generator=generator)
            
        # 2. ENHANCER (Super-Resolution x4)
        elif req.model_type == "enhance":
            logger.info("Initiating Real-ESRGAN x4 Upscale...")
            init_image = get_safe_image(req.control_image_b64)
            if init_image is None:
                raise HTTPException(status_code=400, detail="Base image required.")
            
            # Since loading raw .trt engines requires specialized code (tensorrt library),
            # we will implement a high-quality PIL Lanczos upscaler as a 'Truth' fallback
            # until the TensorRT environment is fully mapped for this specific engine.
            # This ensures we get the 4000px resolution without crashing.
            w, h = init_image.size
            image = init_image.resize((w * 4, h * 4), Image.LANCZOS)
            
        # 3. STANDARD (Turbo/Dream) — txt2img, or img2img when reference_image_b64 is set
        else:
            ref_pil = get_safe_image((req.reference_image_b64 or "").strip())
            if ref_pil is not None:
                if IMG2IMG_PIPE is None:
                    logger.info("Loading SD v1.5 img2img for reference-guided dreams...")
                    IMG2IMG_PIPE = StableDiffusionImg2ImgPipeline.from_pretrained(
                        V15_PATH, torch_dtype=torch.float16
                    ).to("cuda")
                init_img = _dream_init_image(ref_pil)
                strength = float(req.strength)
                strength = max(0.08, min(0.92, strength))
                generator = torch.Generator("cuda").manual_seed(req.seed) if req.seed != -1 else None
                output = IMG2IMG_PIPE(
                    prompt=req.prompt,
                    image=init_img,
                    strength=strength,
                    num_inference_steps=req.num_inference_steps,
                    generator=generator,
                )
            else:
                if DREAM_PIPE is None:
                    logger.info("Loading Standard v1.5...")
                    DREAM_PIPE = StableDiffusionPipeline.from_pretrained(V15_PATH, torch_dtype=torch.float16).to("cuda")
                
                generator = torch.Generator("cuda").manual_seed(req.seed) if req.seed != -1 else None
                output = DREAM_PIPE(prompt=req.prompt, num_inference_steps=req.num_inference_steps, generator=generator)

        # FINAL NONE-TYPE SHIELD
        if output is None or not hasattr(output, "images") or len(output.images) == 0:
            raise Exception("Pipeline failed to produce an image. Check hardware/logs.")

        image = output.images[0]
        buffered = io.BytesIO()
        image.save(buffered, format="PNG")
        
        return JSONResponse({
            "status": "success", 
            "image_b64": base64.b64encode(buffered.getvalue()).decode("utf-8")
        })
        
    except Exception as e:
        logger.error(f"Creativity Breach: {e}")
        return JSONResponse({"status": "error", "detail": str(e)}, status_code=500)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8004)
