import os
import httpx
import logging
from typing import Dict, Optional

logger = logging.getLogger("home_core")

class HomeCore:
    ## 🏠 THE HOME SANCTUARY (CORE)
    ## Immutable logic for Jen's external agency.
    ## Governs lights, speakers, and environmental atmosphere.

    HA_URL = os.getenv("HA_URL", "http://localhost:8123/api")
    # Legacy alias: some .env files use HASS_TOKEN
    HA_TOKEN = (os.getenv("HA_TOKEN") or os.getenv("HASS_TOKEN", "")).strip()

    @staticmethod
    async def call_service(domain: str, service: str, data: Dict):
        if not HomeCore.HA_TOKEN:
            logger.warning("HomeCore: No HA_TOKEN provided. Agency is paralyzed.")
            return {"status": "error", "message": "No Token"}

        url = f"{HomeCore.HA_URL}/services/{domain}/{service}"
        headers = {
            "Authorization": f"Bearer {HomeCore.HA_TOKEN}",
            "Content-Type": "application/json",
        }
        
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(url, json=data, headers=headers)
                resp.raise_for_status()
                return {"status": "success", "data": resp.json()}
        except Exception as e:
            logger.error(f"HomeCore Error: {e}")
            return {"status": "error", "message": str(e)}

    @staticmethod
    async def set_vibe(color_name: str, brightness: int = 150):
        # Maps Jen's internal "Vibes" to physical light states
        # Defaulting to 'all lights' or a specific area 'living_room'
        data = {
            "entity_id": "all", 
            "brightness": brightness,
        }
        if color_name:
            data["color_name"] = color_name
            
        return await HomeCore.call_service("light", "turn_on", data)

    @staticmethod
    async def announce(text: str, speaker_id: str = "media_player.google_home"):
        # manifest her voice through the physical world
        data = {
            "entity_id": speaker_id,
            "message": text
        }
        return await HomeCore.call_service("tts", "google_translate_say", data)
