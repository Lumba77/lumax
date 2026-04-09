"""
Three named OpenAI-compatible API slots (OpenAI, Gemini via Google OpenAI compat, third/aux e.g. Groq).
Configure with LUMAX_REPERTOIRE_* env vars. Used for optional cloud splice alongside local LumaxEngine.

OpenAI pay-as-you-go guard:
  LUMAX_OPENAI_DAILY_MAX_REQUESTS — if > 0, cap successful OpenAI-slot calls per UTC day (state file).
  LUMAX_OPENAI_USAGE_STATE_PATH — optional JSON counter file (default: system temp dir).
  LUMAX_REPERTOIRE_OPENAI_MAX_TOKENS — optional lower max_tokens for OpenAI slot only.
Also set hard limits in the OpenAI / Azure dashboard where available; this is a local safety net.
"""
from __future__ import annotations

import json
import logging
import os
import random
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import httpx

logger = logging.getLogger("cloud_repertoire")

# Default base URLs when BASE_URL is omitted but key+model are set.
_DEFAULT_BASE = {
    "OPENAI": "https://api.openai.com/v1",
    "GEMINI": "https://generativelanguage.googleapis.com/v1beta/openai/",
    "EXTRA": "https://api.groq.com/openai/v1",
}

_SLOT_ORDER = ("OPENAI", "GEMINI", "EXTRA")
_SLOT_PUBLIC_ID = {"OPENAI": "openai", "GEMINI": "gemini", "EXTRA": "extra"}


def _utc_date_iso() -> str:
    return datetime.now(timezone.utc).date().isoformat()


def openai_daily_request_cap() -> int:
    """0 = unlimited local counting (no cap enforced in this module)."""
    try:
        return max(0, int(os.getenv("LUMAX_OPENAI_DAILY_MAX_REQUESTS", "0") or "0"))
    except ValueError:
        return 0


def _openai_usage_state_path() -> str:
    p = os.getenv("LUMAX_OPENAI_USAGE_STATE_PATH", "").strip()
    if p:
        return p
    import tempfile

    return os.path.join(tempfile.gettempdir(), "lumax_openai_daily_usage.json")


def openai_daily_budget_allows() -> bool:
    cap = openai_daily_request_cap()
    if cap <= 0:
        return True
    path = _openai_usage_state_path()
    today = date.today().isoformat()
    count = 0
    if os.path.isfile(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                st = json.load(f)
            if st.get("date") == today:
                count = int(st.get("count", 0))
        except Exception as e:
            logger.warning("cloud_repertoire: OpenAI usage state unreadable (%s), treating as 0", e)
    return count < cap


def openai_budget_record_successful_request() -> None:
    cap = openai_daily_request_cap()
    if cap <= 0:
        return
    path = _openai_usage_state_path()
    today = date.today().isoformat()
    count = 0
    if os.path.isfile(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                st = json.load(f)
            if st.get("date") == today:
                count = int(st.get("count", 0))
        except Exception:
            pass
    count += 1
    try:
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"date": today, "count": count}, f)
    except Exception as e:
        logger.error("cloud_repertoire: could not write OpenAI usage state: %s", e)


def eligible_cloud_slot_ids() -> List[str]:
    """Configured slots minus OpenAI when daily cap is exhausted."""
    slots = [_SLOT_PUBLIC_ID[p] for p in _SLOT_ORDER if slot_credentials(p)]
    if "openai" in slots and not openai_daily_budget_allows():
        slots = [s for s in slots if s != "openai"]
        logger.info(
            "cloud_repertoire: OpenAI slot excluded (daily cap %s reached or exceeded)",
            openai_daily_request_cap(),
        )
    return slots


def _read_slot(prefix: str) -> Tuple[str, str, str, str]:
    key = os.getenv(f"LUMAX_REPERTOIRE_{prefix}_API_KEY", "").strip()
    model = os.getenv(f"LUMAX_REPERTOIRE_{prefix}_MODEL", "").strip()
    base = os.getenv(f"LUMAX_REPERTOIRE_{prefix}_BASE_URL", "").strip()
    if not base:
        base = _DEFAULT_BASE.get(prefix, "")
    label = os.getenv(f"LUMAX_REPERTOIRE_{prefix}_LABEL", prefix.title()).strip() or prefix.title()
    return base, key, model, label


def slot_credentials(prefix: str) -> Optional[Tuple[str, str, str, str]]:
    """Returns (base_url, api_key, model, label) if the slot is usable."""
    base, key, model, label = _read_slot(prefix)
    if key and model and base:
        return base, key, model, label
    return None


def configured_slots_public() -> List[Dict[str, str]]:
    """Safe for logging / prompts — no secrets."""
    out: List[Dict[str, str]] = []
    for p in _SLOT_ORDER:
        cred = slot_credentials(p)
        if not cred:
            continue
        base, _key, model, label = cred
        out.append(
            {
                "id": _SLOT_PUBLIC_ID[p],
                "label": label,
                "model": model,
                "base_host": base.split("//")[-1].split("/")[0][:80],
            }
        )
    return out


def repertoire_sensory_text() -> str:
    slots = configured_slots_public()
    if not slots:
        return ""
    lines = [
        "Remote API slots configured on this deployment (OpenAI-compatible /chat/completions). "
        "Do not claim a provider answered this turn unless routing logs or Daniel confirm it; "
        "local GGUF may still be primary depending on LUMAX_CHAT_PROVIDER / splice.",
    ]
    for s in slots:
        lines.append(f"  — {s['label']} (`{s['id']}`): model `{s['model']}` @ `{s['base_host']}`")
    cap = openai_daily_request_cap()
    if cap > 0 and any(s["id"] == "openai" for s in slots):
        lines.append(
            f"  — OpenAI slot: local daily request cap = {cap} successful calls (UTC day, file-backed); "
            "when exhausted, routing skips OpenAI until midnight UTC unless dashboard limits also apply."
        )
    return "\n".join(lines)


def resolve_cloud_slot(
    request_override: Optional[str],
    env_mode: str,
    splice_percent: int,
) -> Optional[str]:
    """
    Returns public slot id openai|gemini|extra, or None → use local engine.
    request_override: from JSON, e.g. openai|gemini|extra|local|rotate|splice
    env_mode: LUMAX_CHAT_PROVIDER
    """
    slots = eligible_cloud_slot_ids()
    all_configured = [s["id"] for s in configured_slots_public()]
    if not all_configured:
        return None

    o = (request_override or "").strip().lower()
    if o == "local":
        return None
    if o in ("openai", "gemini", "extra"):
        if o not in all_configured:
            logger.warning("cloud_repertoire: requested slot %r not configured", o)
            return None
        if o == "openai" and not openai_daily_budget_allows():
            logger.warning(
                "cloud_repertoire: OpenAI requested but daily cap (%s) reached — falling back",
                openai_daily_request_cap(),
            )
            return None
        return o
    if o == "rotate":
        if not slots:
            return None
        return random.choice(slots)
    if o == "splice":
        p = max(0, min(100, splice_percent))
        if p > 0 and random.randint(1, 100) <= p and slots:
            return random.choice(slots)
        return None

    mode = (env_mode or "local").strip().lower()
    if mode == "local":
        return None
    if mode in ("openai", "gemini", "extra"):
        if mode not in all_configured:
            return None
        if mode == "openai" and not openai_daily_budget_allows():
            return None
        return mode
    if mode == "rotate":
        if not slots:
            return None
        return random.choice(slots)
    if mode in ("splice", "cloud_auto", "auto_splice"):
        p = max(0, min(100, splice_percent))
        if p > 0 and random.randint(1, 100) <= p and slots:
            return random.choice(slots)
        return None
    if mode in ("cloud", "always_cloud"):
        if not slots:
            return None
        return random.choice(slots)
    return None


def _env_prefix_for_public_id(public_id: str) -> Optional[str]:
    for p, pid in _SLOT_PUBLIC_ID.items():
        if pid == public_id.lower():
            return p
    return None


async def openai_compatible_chat(
    base_url: str,
    api_key: str,
    model: str,
    system_text: str,
    user_text: str,
    image_base64: Optional[str] = None,
    max_tokens: Optional[int] = None,
) -> str:
    url = base_url.rstrip("/") + "/chat/completions"
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    mt = max_tokens if max_tokens is not None else int(os.getenv("LUMAX_CLOUD_MAX_TOKENS", "1024") or "1024")
    mt = max(64, min(mt, 8192))

    user_content: Any
    if image_base64:
        user_content = [
            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"}},
            {"type": "text", "text": user_text},
        ]
    else:
        user_content = user_text

    messages: List[Dict[str, Any]] = []
    st = (system_text or "").strip()
    if st:
        messages.append({"role": "system", "content": st})
    messages.append({"role": "user", "content": user_content})

    payload: Dict[str, Any] = {
        "model": model,
        "messages": messages,
        "temperature": float(os.getenv("LUMAX_CLOUD_TEMPERATURE", "0.7") or "0.7"),
        "max_tokens": mt,
    }
    timeout = float(os.getenv("LUMAX_CLOUD_HTTP_TIMEOUT", "120") or "120")
    async with httpx.AsyncClient(timeout=timeout) as client:
        r = await client.post(url, headers=headers, json=payload)
        try:
            r.raise_for_status()
        except httpx.HTTPStatusError as e:
            logger.error("cloud_repertoire: HTTP %s %s", r.status_code, r.text[:500])
            raise
        data = r.json()
    choices = data.get("choices") or []
    if not choices:
        return ""
    msg = choices[0].get("message") or {}
    return (msg.get("content") or "").strip()


async def generate_via_slot(
    public_slot_id: str,
    system_text: str,
    user_text: str,
    image_base64: Optional[str] = None,
) -> str:
    prefix = _env_prefix_for_public_id(public_slot_id)
    if not prefix:
        raise ValueError(f"unknown slot {public_slot_id}")
    cred = slot_credentials(prefix)
    if not cred:
        raise ValueError(f"slot {public_slot_id} not configured")
    base_url, api_key, model, _label = cred
    max_toks: Optional[int] = None
    if prefix == "OPENAI":
        ot = os.getenv("LUMAX_REPERTOIRE_OPENAI_MAX_TOKENS", "").strip()
        if ot.isdigit():
            max_toks = int(ot)
    out = await openai_compatible_chat(
        base_url,
        api_key,
        model,
        system_text,
        user_text,
        image_base64=image_base64,
        max_tokens=max_toks,
    )
    if prefix == "OPENAI" and (out or "").strip():
        openai_budget_record_successful_request()
    return out
