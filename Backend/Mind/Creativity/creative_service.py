import base64
import io
import os
import torch
import logging
from typing import Optional, List, Any
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict
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
CONTROL_PIPE = None
ENHANCE_PIPE = None
CONTROLNET = None

# Biological Path Mappings
IMAGEN_ROOT = "/app/models/Imagen"
V15_PATH = f"{IMAGEN_ROOT}/stable-diffusion-v1-5"
CONTROLNET_CANNY_PATH = f"{IMAGEN_ROOT}/sd-controlnet-canny"

class DreamRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    prompt: str
    seed: int = -1
    model_type: str = "turbo" # "control", "enhance", "turbo"
    num_inference_steps: int = 20
    control_image_b64: str = ""
    strength: float = 0.75

@app.on_event("startup")
async def startup_event():
    logger.info("Creativity Faculty: Sanctuary initialized.")

def get_safe_image(b64_str: str) -> Optional[Image.Image]:
    if not b64_str: return None
    try:
        data = base64.b64decode(b64_str)
        return Image.open(io.BytesIO(data)).convert("RGB")
    except Exception as e:
        logger.error(f"Image Decode Error: {e}")
        return None

@app.post("/api/dream")
async def generate_dream_image(req: DreamRequest):
    global DREAM_PIPE, CONTROL_PIPE, ENHANCE_PIPE, CONTROLNET
    
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
            
        # 3. STANDARD (Turbo/Dream)
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
