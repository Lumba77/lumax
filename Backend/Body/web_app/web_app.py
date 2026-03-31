import os
import logging
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.staticfiles import StaticFiles
import httpx
import uvicorn

# Configure Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("WebAppBridge")

app = FastAPI(title="Lumax Web App Bridge")

# Paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SOUL_URL = os.getenv("SOUL_URL", "http://lumax_soul:8000")
EARS_URL = os.getenv("EARS_URL", "http://lumax_ears:8001")

@app.get("/", response_class=HTMLResponse)
async def get_index():
    return FileResponse(os.path.join(BASE_DIR, "index.html"))

@app.get("/manifest.json")
async def get_manifest():
    return {
        "name": "Lumax Soul Nexus",
        "short_name": "Lumax",
        "start_url": "/",
        "display": "standalone",
        "background_color": "#02050a",
        "theme_color": "#00f3ff",
        "icons": [
            {
                "src": "https://img.icons8.com/neon/512/artificial-intelligence.png",
                "sizes": "512x512",
                "type": "image/png"
            }
        ]
    }

@app.post("/api/chat")
async def proxy_chat(request: Request):
    data = await request.json()
    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(f"{SOUL_URL}/compagent", json=data)
        return resp.json()

@app.post("/api/stt")
async def proxy_stt(request: Request):
    data = await request.json()
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(f"{EARS_URL}/stt", json=data)
        return resp.json()

@app.get("/api/vitals")
async def proxy_vitals():
    async with httpx.AsyncClient(timeout=5.0) as client:
        resp = await client.get(f"{SOUL_URL}/vitals")
        return resp.json()

@app.post("/api/update_soul")
async def proxy_update_soul(request: Request):
    data = await request.json()
    async with httpx.AsyncClient(timeout=5.0) as client:
        resp = await client.post(f"{SOUL_URL}/update_soul", json=data)
        return resp.json()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
