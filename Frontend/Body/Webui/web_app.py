import copy
import os
import json
import hashlib
import logging
import secrets
from typing import Any

from fastapi import Body, Depends, FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, FileResponse
from pydantic import BaseModel, Field
from starlette.middleware.sessions import SessionMiddleware
import httpx
import uvicorn

# Configure Logging (routine request logs: uvicorn access_log off by default)
logging.basicConfig(level=os.getenv("LOG_LEVEL", "WARNING"))
logger = logging.getLogger("WebAppBridge")


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


# --- Web UI gate (set LUMAX_WEBUI_PASSWORD in .env / compose; never expose port 8080 without it on public networks) ---
WEBUI_PASSWORD = os.getenv("LUMAX_WEBUI_PASSWORD", "").strip()
WEBUI_SESSION_SECRET = os.getenv("LUMAX_WEBUI_SESSION_SECRET", "").strip()
SESSION_KEY_OK = "lumax_webui_ok"


def _webui_session_secret() -> str:
    if WEBUI_SESSION_SECRET:
        return WEBUI_SESSION_SECRET
    if WEBUI_PASSWORD:
        return hashlib.sha256(("lumax-webui|" + WEBUI_PASSWORD).encode()).hexdigest()
    return "lumax-webui-dev-insecure-fixed-do-not-use-in-production"


app = FastAPI(title="Lumax Web App Bridge")
# Session cookie: one login until max_age (or secret change). SameSite=Lax, path=/ for all /api routes.
# Same host for every visit or the cookie will not apply:
#   - localhost vs 127.0.0.1 are different origins.
#   - Raw LAN IPs (192.168.x.x) are each their own origin; if DHCP gives the PC a new IP, that URL
#     changes and you must sign in again. Prefer a stable name: router DHCP reservation + fixed IP,
#     or use http://<PC-hostname>.local:8080 (mDNS) / your LAN DNS name so the URL stays the same
#     when the address behind it changes.
app.add_middleware(
    SessionMiddleware,
    secret_key=_webui_session_secret(),
    max_age=int(os.getenv("LUMAX_WEBUI_SESSION_MAX_AGE", str(7 * 24 * 3600))),
    same_site="lax",
    https_only=False,
    path="/",
    session_cookie=os.getenv("LUMAX_WEBUI_SESSION_COOKIE", "lumax_webui_session"),
)


class LoginBody(BaseModel):
    password: str = Field("", max_length=4096)


async def require_webui_login(request: Request) -> None:
    """Require a prior successful POST /api/auth/login when LUMAX_WEBUI_PASSWORD is set."""
    if not WEBUI_PASSWORD:
        return
    if request.session.get(SESSION_KEY_OK):
        return
    raise HTTPException(status_code=401, detail="Not authenticated")


@app.get("/api/auth/status")
async def auth_status(request: Request) -> dict[str, Any]:
    if not WEBUI_PASSWORD:
        return {"auth_required": False, "authenticated": True}
    return {
        "auth_required": True,
        "authenticated": bool(request.session.get(SESSION_KEY_OK)),
    }


def _password_matches(given: str) -> bool:
    try:
        return secrets.compare_digest(WEBUI_PASSWORD, given)
    except (TypeError, ValueError):
        return False


@app.post("/api/auth/login")
async def auth_login(request: Request, body: LoginBody) -> dict[str, bool]:
    if not WEBUI_PASSWORD:
        request.session[SESSION_KEY_OK] = True
        return {"ok": True}
    if not _password_matches(body.password):
        raise HTTPException(status_code=401, detail="Invalid password")
    request.session[SESSION_KEY_OK] = True
    return {"ok": True}


@app.post("/api/auth/logout")
async def auth_logout(request: Request) -> dict[str, bool]:
    request.session.clear()
    return {"ok": True}

# Paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ANNOUNCEMENTS_PATH = os.path.join(BASE_DIR, "announcements.json")
UI_CONFIG_PATH = os.getenv("LUMAX_UI_CONFIG_PATH", os.path.join(BASE_DIR, "lumax_ui_config.json"))
LEGACY_BRANDING_PATH = os.path.join(BASE_DIR, "webui_branding.json")
SOUL_URL = os.getenv("SOUL_URL", "http://lumax_soul:8000")
EARS_URL = os.getenv("EARS_URL", "http://lumax_ears:8001")

# Shared across browser + VR: identity strings. Web-only (nav, auth, PWA) lives under "web".
GLOBAL_KEYS = frozenset({"site_name", "slogan", "ready_message"})

_BRAND_STR_MAX = 4000
_BRAND_NAV_KEYS = frozenset(
    (
        "SANCTUARY",
        "NEURAL",
        "THOUGHTS",
        "IMAGINE",
        "VISION",
        "VESSEL",
        "AGENCY",
        "SOCIAL",
        "COWORK",
        "NUCLEUS",
        "UTILS",
        "BRANDING",
    )
)
_BRAND_GROUP_KEYS = frozenset(("cognition", "manifestation", "agency", "laboratory", "utilities"))


def _default_branding() -> dict[str, Any]:
    return {
        "site_name": "Lumax",
        "page_title": "Lumax — Your everything for life",
        "slogan": "Your everything for life.",
        "manifest_short_name": "Lumax",
        "auth_blurb": (
            "Sign in once to unlock this console; your browser keeps the session until it expires "
            "or site data is cleared. Optional cloud features may ask you to sign in separately."
        ),
        "auth_continue_button": "Continue",
        "consent_title": "Privacy",
        "consent_body": (
            "Session and environment data may be used to improve your companion’s behavior. "
            "Treat sensitive inputs accordingly. You can stop using the UI at any time."
        ),
        "consent_button": "I understand",
        "header_status_prefix": "Godot · VR ·",
        "footer_stack": "Stack: local + optional cloud",
        "nav_groups": {
            "cognition": "Cognition",
            "manifestation": "Manifestation",
            "agency": "Agency",
            "laboratory": "Laboratory",
            "utilities": "Utilities",
        },
        "nav_tabs": {
            "SANCTUARY": "CHRONICLE",
            "NEURAL": "ETHOS (PERSONA)",
            "THOUGHTS": "LOGOS (COG)",
            "IMAGINE": "DREAMSCAPE (ART)",
            "VISION": "SPECTRAL VIEW",
            "VESSEL": "VESSEL RIG",
            "AGENCY": "AUTONOMOUS",
            "SOCIAL": "MULTIVERSE",
            "COWORK": "RATATOSK (CODE)",
            "NUCLEUS": "NUCLEUS (DEBUG)",
            "UTILS": "ANNOUNCE BOARD",
            "BRANDING": "LABEL EDITOR",
        },
        "chat_placeholder": "Transmit thoughts to Jen...",
        "utils_title": "Announcements",
        "utils_blurb": (
            "Operational notices and reminders. Content is served from announcements.json "
            "next to the Web UI (editable on disk)."
        ),
        "ready_message": "Connected. Lumax Web UI is ready.",
    }


def _clamp_str(val: Any, max_len: int = _BRAND_STR_MAX) -> str:
    if val is None:
        return ""
    s = str(val).strip()
    return s[:max_len]


def _default_mobile() -> dict[str, Any]:
    """Reserved for Android / React Native / Capacitor APK — fetch GET /api/ui_config and read `mobile`."""
    return {
        "labels": {},
        "nav": {},
    }


def _default_desktop() -> dict[str, Any]:
    """Reserved for Godot/Electron desktop shell — same pattern as `godot_vr`."""
    return {
        "labels": {},
        "nav": {},
    }


def _merge_client_stub_dict(defaults: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    """Shallow merge for open-ended mobile/desktop sections."""
    out = copy.deepcopy(defaults)
    if not isinstance(overlay, dict):
        return out
    for k, v in overlay.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            merged = dict(out[k])
            merged.update(v)
            out[k] = merged
        else:
            out[k] = v
    return out


def _default_godot_vr() -> dict[str, Any]:
    return {
        "hubs": {
            "MIND": ["PSYCHE", "SOUL", "BRAINS", "MEMORY", "EMOTIONS"],
            "BODY": ["VESSEL", "AGENCY", "VITALS"],
            "MANIFEST": ["IMAGEN", "VIDGEN", "MEDIA"],
            "CORE": ["CHAT", "LOGS", "SETTINGS", "SYSTEM", "FILES"],
        },
        "ribbon_labels": {
            "MIND": "MIND",
            "BODY": "BODY",
            "MANIFEST": "MANIFEST",
            "CORE": "CORE",
        },
        "tab_labels": {},
    }


def _default_ui_config() -> dict[str, Any]:
    flat = _default_branding()
    return {
        "version": 1,
        "global": {k: flat[k] for k in GLOBAL_KEYS},
        "web": {k: flat[k] for k in flat if k not in GLOBAL_KEYS},
        "godot_vr": _default_godot_vr(),
        "mobile": _default_mobile(),
        "desktop": _default_desktop(),
    }


def _migrate_legacy_flat_to_ui_config(leg: dict[str, Any]) -> dict[str, Any]:
    g = {k: leg[k] for k in GLOBAL_KEYS if k in leg}
    w = {k: v for k, v in leg.items() if k not in GLOBAL_KEYS}
    return {
        "version": 1,
        "global": g,
        "web": w,
        "godot_vr": _default_godot_vr(),
        "mobile": _default_mobile(),
        "desktop": _default_desktop(),
    }


def _merge_godot_vr_dicts(defaults: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    out = copy.deepcopy(defaults)
    if not isinstance(overlay, dict):
        return out
    if isinstance(overlay.get("hubs"), dict):
        for hk, lst in overlay["hubs"].items():
            if isinstance(lst, list):
                out["hubs"][hk] = [str(x)[:64] for x in lst]
    if isinstance(overlay.get("ribbon_labels"), dict):
        for k, v in overlay["ribbon_labels"].items():
            out["ribbon_labels"][k] = _clamp_str(v, 200)
    if isinstance(overlay.get("tab_labels"), dict):
        for k, v in overlay["tab_labels"].items():
            out["tab_labels"][k] = _clamp_str(v, 200)
    return out


def _merge_ui_config_with_defaults(defaults: dict[str, Any], loaded: dict[str, Any]) -> dict[str, Any]:
    out = copy.deepcopy(defaults)
    out["version"] = int(loaded.get("version", 1))
    lg = loaded.get("global")
    if isinstance(lg, dict):
        for k in GLOBAL_KEYS:
            if k in lg:
                out["global"][k] = _clamp_str(lg[k])
    lw = loaded.get("web")
    if isinstance(lw, dict) and len(lw) > 0:
        def_flat = _default_branding()
        merged_web: dict[str, Any] = copy.deepcopy(out["web"])
        for k, v in lw.items():
            if k == "nav_groups" and isinstance(v, dict):
                g = dict(merged_web.get("nav_groups") or def_flat["nav_groups"])
                for gk, gv in v.items():
                    if gk in _BRAND_GROUP_KEYS:
                        g[gk] = _clamp_str(gv, 500)
                merged_web["nav_groups"] = g
            elif k == "nav_tabs" and isinstance(v, dict):
                t = dict(merged_web.get("nav_tabs") or def_flat["nav_tabs"])
                for tk, tv in v.items():
                    if tk in _BRAND_NAV_KEYS:
                        t[tk] = _clamp_str(tv, 500)
                merged_web["nav_tabs"] = t
            elif k in def_flat and k not in ("nav_groups", "nav_tabs"):
                merged_web[k] = _clamp_str(v)
        out["web"] = merged_web
    out["godot_vr"] = _merge_godot_vr_dicts(defaults["godot_vr"], loaded.get("godot_vr") or {})
    out["mobile"] = _merge_client_stub_dict(
        out.get("mobile") or _default_mobile(),
        loaded.get("mobile") or {},
    )
    out["desktop"] = _merge_client_stub_dict(
        out.get("desktop") or _default_desktop(),
        loaded.get("desktop") or {},
    )
    return out


def _load_ui_config() -> dict[str, Any]:
    d = _default_ui_config()
    if os.path.isfile(UI_CONFIG_PATH):
        try:
            with open(UI_CONFIG_PATH, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, dict):
                d = _merge_ui_config_with_defaults(d, loaded)
        except Exception as e:
            logger.warning("lumax_ui_config.json unreadable: %s", e)
    elif os.path.isfile(LEGACY_BRANDING_PATH):
        try:
            with open(LEGACY_BRANDING_PATH, "r", encoding="utf-8") as f:
                leg = json.load(f)
            if isinstance(leg, dict) and "version" not in leg:
                d = _migrate_legacy_flat_to_ui_config(leg)
                _save_ui_config(d)
                logger.info("Migrated %s to unified %s", LEGACY_BRANDING_PATH, UI_CONFIG_PATH)
        except Exception as e:
            logger.warning("legacy webui_branding.json unreadable: %s", e)
    return d


def _save_ui_config(cfg: dict[str, Any]) -> None:
    parent = os.path.dirname(UI_CONFIG_PATH)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(UI_CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")


def _effective_web_flat(cfg: dict[str, Any]) -> dict[str, Any]:
    """Flatten global + web layers for the browser (backward-compatible /api/branding)."""
    base = _default_branding()
    g = cfg.get("global") or {}
    w = cfg.get("web") or {}
    for k in GLOBAL_KEYS:
        if k in g:
            base[k] = _clamp_str(g[k])
    defaults = _default_branding()
    for k, v in w.items():
        if k == "nav_groups" and isinstance(v, dict):
            merged = dict(base["nav_groups"])
            for gk, gv in v.items():
                if gk in _BRAND_GROUP_KEYS:
                    merged[gk] = _clamp_str(gv, 500)
            base["nav_groups"] = merged
        elif k == "nav_tabs" and isinstance(v, dict):
            merged = dict(base["nav_tabs"])
            for tk, tv in v.items():
                if tk in _BRAND_NAV_KEYS:
                    merged[tk] = _clamp_str(tv, 500)
            base["nav_tabs"] = merged
        elif k in defaults and k not in ("nav_groups", "nav_tabs"):
            base[k] = _clamp_str(v)
    return base


def _merge_flat_patch_into_ui_config(cfg: dict[str, Any], patch: dict[str, Any]) -> dict[str, Any]:
    out = copy.deepcopy(cfg)
    g = dict(out.get("global") or {})
    w = dict(out.get("web") or {})
    def_flat = _default_branding()
    for k, v in patch.items():
        if k in GLOBAL_KEYS:
            g[k] = _clamp_str(v)
        elif k == "nav_groups" and isinstance(v, dict):
            cur = dict(w.get("nav_groups") or def_flat["nav_groups"])
            for gk, gv in v.items():
                if gk in _BRAND_GROUP_KEYS:
                    cur[gk] = _clamp_str(gv, 500)
            w["nav_groups"] = cur
        elif k == "nav_tabs" and isinstance(v, dict):
            cur = dict(w.get("nav_tabs") or def_flat["nav_tabs"])
            for tk, tv in v.items():
                if tk in _BRAND_NAV_KEYS:
                    cur[tk] = _clamp_str(tv, 500)
            w["nav_tabs"] = cur
        elif k in def_flat and k not in ("nav_groups", "nav_tabs"):
            w[k] = _clamp_str(v)
    out["global"] = g
    out["web"] = w
    out["version"] = 1
    return out


def _load_branding() -> dict[str, Any]:
    return _effective_web_flat(_load_ui_config())

_DEFAULT_ANNOUNCEMENTS = {
    "items": [
        {
            "date": "2026-04-07",
            "tag": "NAME",
            "title": "Why Lumax?",
            "body": "Lumax is Lumen Maximum—light turned all the way up. Your everything for life: “your” anchors it in one person; “everything” refuses a thin category—we mean companion and agent together, the full arc. The line is also meant to breathe: a little poetic, life-giving in the sense of support that sustains and enlivens, not only performs. The sound sits next to my nickname, Lumba—same opening, grown into a name built to outlast a single person.",
            "priority": "info",
        },
        {
            "date": "2026-04-07",
            "tag": "NETWORK",
            "title": "Tailscale + Cloudflare",
            "body": "Subnet router on the always-on box; public entry via Cloudflare Tunnel when needed. See ops notes.",
            "priority": "info",
        },
        {
            "date": "2026-04-07",
            "tag": "UI",
            "title": "Announce board",
            "body": "Edit Frontend/Body/Webui/announcements.json to post vessel-wide bulletins.",
            "priority": "ops",
        },
    ]
}


def _load_announcements():
    if os.path.isfile(ANNOUNCEMENTS_PATH):
        try:
            with open(ANNOUNCEMENTS_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and isinstance(data.get("items"), list):
                return data
        except Exception as e:
            logger.warning("announcements.json unreadable: %s", e)
    return dict(_DEFAULT_ANNOUNCEMENTS)

@app.get("/", response_class=HTMLResponse)
async def get_index():
    return FileResponse(os.path.join(BASE_DIR, "index.html"))

@app.get("/manifest.json")
async def get_manifest():
    b = _load_branding()
    return {
        "name": b.get("page_title") or "Lumax",
        "short_name": b.get("manifest_short_name") or "Lumax",
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


@app.get("/api/branding")
async def get_branding() -> dict[str, Any]:
    """Public read so the login screen and shell can show custom names before auth."""
    return _load_branding()


@app.put("/api/branding")
async def put_branding(
    body: dict[str, Any] = Body(...),
    _auth: None = Depends(require_webui_login),
) -> dict[str, Any]:
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="JSON object required")
    cfg = _load_ui_config()
    cfg = _merge_flat_patch_into_ui_config(cfg, body)
    _save_ui_config(cfg)
    return _effective_web_flat(cfg)


@app.get("/api/ui_config")
async def get_ui_config() -> dict[str, Any]:
    """Unified UI: global + per-client sections (web, godot_vr, mobile, desktop). Public read on LAN."""
    cfg = _load_ui_config()
    return {
        "version": cfg.get("version", 1),
        "global": cfg.get("global") or {},
        "web": cfg.get("web") or {},
        "godot_vr": cfg.get("godot_vr") or _default_godot_vr(),
        "mobile": cfg.get("mobile") or _default_mobile(),
        "desktop": cfg.get("desktop") or _default_desktop(),
        "effective_web": _effective_web_flat(cfg),
    }

@app.post("/api/chat")
async def proxy_chat(request: Request, _auth: None = Depends(require_webui_login)):
    data = await request.json()
    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(f"{SOUL_URL}/compagent", json=data)
        return resp.json()

@app.post("/api/stt")
async def proxy_stt(request: Request, _auth: None = Depends(require_webui_login)):
    data = await request.json()
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(f"{EARS_URL}/stt", json=data)
        return resp.json()

@app.get("/api/announcements")
async def get_announcements(_auth: None = Depends(require_webui_login)):
    """Bulletins for the Web UI Utils → Announce Board tab."""
    return _load_announcements()


@app.get("/api/vitals")
async def proxy_vitals(_auth: None = Depends(require_webui_login)):
    async with httpx.AsyncClient(timeout=5.0) as client:
        resp = await client.get(f"{SOUL_URL}/vitals")
        return resp.json()

@app.post("/api/update_soul")
async def proxy_update_soul(request: Request, _auth: None = Depends(require_webui_login)):
    data = await request.json()
    async with httpx.AsyncClient(timeout=5.0) as client:
        resp = await client.post(f"{SOUL_URL}/update_soul", json=data)
        return resp.json()

if __name__ == "__main__":
    _port = int(os.getenv("WEBUI_PORT", "8080"))
    _auth_note = " password gate ON (set LUMAX_WEBUI_PASSWORD)" if WEBUI_PASSWORD else " no password gate (set LUMAX_WEBUI_PASSWORD for public hosts)"
    print(
        f"[web_app] :{_port} — uvicorn log={_uvicorn_log_level()} access_log={_uvicorn_access_log()};{_auth_note}",
        flush=True,
    )
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=_port,
        log_level=_uvicorn_log_level(),
        access_log=_uvicorn_access_log(),
    )
