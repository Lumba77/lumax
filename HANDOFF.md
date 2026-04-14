# LUMAX handoff — Web UI + VR (current stack)

**Purpose:** Get the next session to **full speed** on the **ops Web UI** and **Godot VR** against the **same** Docker stack: soul, body, creativity, Chatterbox TTS, optional Turbo, in-stack Ollama, HA.

**Typical branch:** `chore/lumax-cognition-docker-webui-preflight-cleanup` → `origin` on `https://github.com/Lumba77/lumax`.

---

## Quick start (developer)

1. **Stack up** (repo root, `.env` beside `docker-compose.yml`):  
   `docker compose up -d`
2. **Web UI:** `http://127.0.0.1:8080` — sign in with `LUMAX_WEBUI_PASSWORD` from `.env`.
3. **Smoke tests (current defaults):**  
   `.\scripts\run_all_tests.ps1`  
   - Covers: ops login → **IMAGINE** `/api/dream` → **Chatterbox** TTS → **Piper** fallback.  
   - Optional older pipeline (STT → soul → mouth):  
     `.\scripts\run_all_tests.ps1 -LegacySmoke`
4. **VR:** Open Godot **4.6.x** on `Godot/` — same soul on `:8000`; ribbon/config patterns align with `lumax_ui_config.json` (see **VR** below).

**Feature maturity (what’s “done” vs placeholder):** see **`FEATURE_INVENTORY.md`** in the repo root. **`http://127.0.0.1:8080` → Utilities → FEATURE MAP** serves the same document with **filters** (tier, section, search, presets) after login — source file must exist at repo root on the host (`FEATURE_INVENTORY.md` → `/app/FEATURE_INVENTORY.md` in Docker). After `git pull` or editing `web_app.py`, **`docker restart lumax_ops`** (uvicorn does not auto-reload) or the **`GET /api/feature_inventory`** route may 404 until the process restarts.

---

## Architecture (what talks to what)

Single `lumax_unified` image with repo `.: /app` on network `lumax_local`:

| Service | Ports | Role |
|--------|-------|------|
| `lumax_soul` | 8000 | Cognitive core (`compagent.py` / FastAPI) |
| `lumax_body` | 8001–8002 | Ears (STT) + Mouth (TTS router) |
| `lumax_creativity` | **8003** | Image generation — `creative_service.py`, `POST /api/dream`, catalog, health |
| `lumax_ops` | **8080**, 8006 | **Primary Web UI** (`Frontend/Body/Webui`) + tools + **autonomous sentry** |
| `lumax_chatterbox_resemble` | **8004** (host) | **Resemble Chatterbox** Web UI + API (emotional TTS) — **not** started by default compose file alone; see **TTS stacks** |
| `lumax_turbochat` | 8005 | **XTTS ONNX** turbo speech (alternate mouth backend) — **compose profile `turbo`**: not started by default; use `--profile turbo` or `COMPOSE_PROFILES=turbo` |
| `lumax_ollama_backup` | 11434 | In-stack Ollama (embeddings, helpers, sentry solver, etc.) |
| `lumax_homeassistant` | **8123** | Home Assistant — `./Backend/HomeAssistant` → `/config` (**do not commit** live secrets — `.gitignore`) |

**In-stack Ollama:** `OLLAMA_HOST=http://lumax_ollama_backup:11434` (soul + tools).  
**Soul → creativity:** `CREATIVE_SERVICE_URL=http://lumax_creativity:8003` (`lumax_ops` + compose).

---

## Web UI (`lumax_ops` :8080)

**Code:** `Frontend/Body/Webui/web_app.py` + `index.html`.  
**Copy / structure:** `Frontend/Body/Webui/lumax_ui_config.json` — `global`, `web`, `godot_vr`, `mobile`, `desktop`.

**Auth:** `LUMAX_WEBUI_PASSWORD` — session cookie; many `/api/*` routes require login.  
**Public read:** `GET /api/ui_config` (used by shells before auth).  
**CORS:** `LUMAX_WEBUI_CORS_ORIGINS` for Vite / Capacitor (`https://localhost`, `ionic://`, `capacitor://`, etc.).

**Important routes (grep `web_app.py` for the full list):**

| Area | Role |
|------|------|
| `/api/auth/login`, `/api/auth/status` | Session |
| `/api/dream`, `/api/dream/catalog` | Proxy to **`lumax_creativity`** (logged in) |
| `/api/creativity/status`, `/api/creativity/health` | Upstream creativity health |
| `/api/tts/backend` (GET/PUT) | Persists mouth routing file inside container (`Backend/preflight/tts_backend`) |
| CHATTERBOX tab | iframe / URL from env (`LUMAX_CHATTERBOX_UI_URL`, `CHATTERBOX_UI_PORT`) |

**IMAGINE tab:** Browser loads catalog → posts to **`/api/dream`** on ops → creativity. For failures, check `docker logs lumax_creativity` and `GET :8003/api/health`.

---

## TTS stacks (Chatterbox vs Turbo)

**Rule of thumb on one GPU:** run **either** Chatterbox **or** Turbo as the heavy GPU TTS, not both at full tilt.

**Current product default:** **Chatterbox (Resemble)** for emotional speech, **Piper** as automatic fallback if Chatterbox errors (`Backend/Body/body_interface.py`).

- **Compose:** `LUMAX_TTS_BACKEND` defaults to **`chatterbox`** for `lumax_body`; `LUMAX_CHATTERBOX_HTTP_URL` points at `http://lumax_chatterbox_resemble:8004`.
- **Persistent choice:** first line of `Backend/preflight/tts_backend` — `chatterbox` or `turbo` (hot path without env churn).
- **Switch script (GPU stack):**  
  - `.\scripts\switch_gpu_tts_stack.ps1 ChatterboxUi` — stops `lumax_turbochat`, starts Chatterbox overlay, writes `tts_backend`.  
  - `.\scripts\switch_gpu_tts_stack.ps1 Xtts` — the inverse.  
  Uses **both** `docker-compose.yml` and `docker-compose.chatterbox-resemble.yml`.

**Chatterbox bring-up:** `scripts/bootstrap_chatterbox_resemble.ps1` (clone/build paths).  
**UI:** `http://localhost:8004` (or `CHATTERBOX_UI_PORT`).

---

## Creativity & IMAGINE (`lumax_creativity` :8003)

**Service:** `Backend/Mind/Creativity/creative_service.py`.

**API:** `GET /health`, `GET /api/health`, `GET /api/dream/catalog`, `POST /api/dream`.

**Compose:** `lumax_creativity` has an **NVIDIA GPU reservation**; mounts `LUMAX_MODELS_ROOT` → `/app/models`. Cold start runs `pip install` for dream deps — can be slow once.

**Local SD1.5 (txt2img):**

- Default tree: `Mind/Creativity/Imagen/stable-diffusion-v1-5` under `LUMAX_MODELS_ROOT`.
- **`model_index.json` must describe a plain `StableDiffusionPipeline`**, not a ControlNet pipeline snapshot. A mistaken ControlNet-style index caused load failures; the repo includes resolution logic + tokenizer fixes where applicable.
- Override explicitly: **`LUMAX_CREATIVITY_SD15_MODEL_ID`** in `.env` / compose (path inside container or Hub repo id).
- Hub fallback: optional; disable with **`LUMAX_CREATIVITY_DISABLE_SD15_HUB_FALLBACK=1`** only when you have a complete offline tree.

**Supporting:** `invokeai_catalog_bridge.py`, InvokeAI CSV merge, Spandrel upscalers, `lumax_imagen_catalog.json`.

---

## Ollama (`lumax_ollama_backup`)

**Healthcheck:** `curl -sf http://127.0.0.1:11434/api/tags` (image installs `curl`). Rebuild image if an old layer lacked tools.

---

## Ops bootstrap

- **`scripts/run_lumax_ops.sh`** — bootstrap + uvicorn `web_app` :8080 + `autonomous_sentry.py`.
- **`LUMAX_WEBUI_RELOAD`** (default **1** in compose) — uvicorn **`--reload`** on `/app/Frontend/Body/Webui` so bind-mounted edits to **`web_app.py`** / **`index.html`** hot-restart without `docker restart lumax_ops`. After changing `run_lumax_ops.sh` or this env, **`docker compose up -d --force-recreate lumax_ops`** once. Set **`LUMAX_WEBUI_RELOAD=0`** in `.env` if you disable reload in production.
- **`scripts/lumax_ops_webui_bootstrap.py`** — may be untracked locally; required in containers if documented.

---

## Tests (smoke)

| Command | What it runs |
|---------|----------------|
| `.\scripts\run_all_tests.ps1` | **`tests/smoke_ops_imagine_tts.py`** — ops auth, IMAGINE, Chatterbox + Piper fallback (**default, matches current stack**). |
| `.\scripts\run_all_tests.ps1 -LegacySmoke` | Also runs **`tests/smoke_stt_thinking_tts.py`** — older EARS → soul → MOUTH pipe (probes Turbo **or** Chatterbox based on mouth backend). |

Details: `tests/README.md`.

---

## Godot VR (Windows + Quest) — handoff for the next session

**Goal:** VR uses the **same Docker soul** as the Web UI (`lumax_soul` **:8000**), optional EARS **:8001**, mouth/TTS **:8002**. Godot does **not** mirror every browser tab; it has its **own** ribbon console (`WebUI.gd`) plus **Synapse** HTTP and **SkeletonKey** scene wiring.

### Project & editor

- **Open in Godot:** `Godot/project.godot` — version **4.6.x** (local editor, e.g. `div/files/godot/`).
- **Core scenes / entry:** search for main scenes your branch uses (e.g. `Lumax_Core.tscn`, `Body/*.tscn`); **SkeletonKey** is the usual VR “nexus” attaching WebUI + Synapse.

### Must-read scripts (Lumax-owned)

| Area | File | Role |
|------|------|------|
| VR ↔ soul HTTP | `Godot/Soul/Synapse.gd` | `compagent`, STT `:8001/stt`, `update_soul`, `switch_model`, runtime config, vitals, `list_files`, `memory_archive`, sensory channel. LAN: `lumax_network_config.json`, `user://lumax_soul_host.txt`. |
| In-headset UI | `Godot/Mind/WebUI.gd` | Loads **`/api/ui_config`** (`LUMAX_UI_CONFIG_URL` or `http://127.0.0.1:8080`); TTS backend GET/PUT **:8002**; ribbon tabs (Vessel VRM scan, Brains → signal, Memory, Files, emotions — mixed live vs stub). |
| Wiring hub | `Godot/Nexus/SkeletonKey.gd` | Connects WebUI signals (e.g. **`brain_selected` → `Synapse.switch_model`**), vitals, soul sliders, XR/passthrough, vision paths. |
| Director / fate | `Godot/scripts/director_manager.gd` | `compagent` channels `director` / `summary`; tag parsing; vision snapshots when enabled. |
| Multiplayer | `Godot/Nexus/MultiplayerManager.gd` | ENet; **`lumax_network_config.json`**. |
| Room context | `Godot/Senses/RoomSpatialContext.gd` | `lumax_room_entity`, `lumax_room_camera` for soul context. |

Stubby areas are documented in **`FEATURE_INVENTORY.md` §4** (manifest IMAGEN/VIDGEN/MEDIA, Agency panel, Files `ACCESS_DENIED`, etc.).

### Config & networking

- **Unified JSON:** `Frontend/Body/Webui/lumax_ui_config.json` → section **`godot_vr`** (hubs/labels) — Web UI **LABEL EDITOR** can tweak **web** copy; Godot merges **`GET /api/ui_config`** at runtime.
- **Quest / LAN:** PC IP for soul: **`res://lumax_network_config.json`** or user override; optional scripts like **`connect_quest.ps1`** (branch-dependent). Same **`lumax_local`** Docker network when testing tethered.

### Verification order (VR)

1. Docker stack up (`docker compose up -d`); soul **:8000** healthy.
2. Godot **Play** (desktop XR or Quest): confirm Synapse reaches soul (chat, vitals if wired).
3. Exercise ribbon: **SYSTEM** runtime, **Brains** (if SkeletonKey connected), **Vessel** VRM list — compare with **FEATURE MAP → Godot** filter in Web UI.

### Next session checklist (Godot-first)

Use Web UI **FEATURE MAP** to focus the work:
- Preset: **Godot / VR**
- Tiers: start with **C** (stubs), then **B** (hardening)
- Useful search: `ACCESS_DENIED`, `TRAPPED`, `emotion`, `manifest`, `brain_selected`

1. **Files panel activation (`Godot/Mind/WebUI.gd`)**
   - Scope: replace activation `ACCESS_DENIED` path with a real action (open/import/request details) or explicit disabled UX.
   - Acceptance:
     - Selecting an item triggers deterministic behavior (no dead click).
     - Success/failure message is shown in-panel.
     - No regression in file list population from Synapse (`list_files` flow).

2. **Emotions grid wiring (`Godot/Mind/WebUI.gd` + `Godot/Soul/Synapse.gd`)**
   - Scope: wire at least 3 chat-only emotion buttons to real soul events/channels (or hide those buttons behind a clear disabled state).
   - Acceptance:
     - Clicked buttons emit a real signal/request (not only `add_message`).
     - Result path is observable (UI message and/or Synapse callback).
     - Existing wired actions (`SENSE_ENV`, `DREAM`, `DIAGNOSTIC`, verify/certify) keep working.

3. **Manifest IMAGEN MVP (`Godot/Mind/WebUI.gd` + backend route already present)**
   - Scope: convert one manifest action from `TRAPPED ... ACTION` to a real request/response loop.
   - Acceptance:
     - One complete flow: trigger -> request sent -> response handled -> user feedback shown.
     - Error state is explicit (timeout/backend error copy).
     - No crash when backend is unavailable.

4. **Brains UX hardening (`Godot/Mind/WebUI.gd` ↔ `Godot/Nexus/SkeletonKey.gd`)**
   - Scope: keep existing `brain_selected -> Synapse.switch_model`, add clear progress and failure handling.
   - Acceptance:
     - Selecting a brain always shows "switching" state.
     - Success and failure outcomes are distinguishable in UI.
     - Repeated taps cannot spam-switch uncontrolled (basic guard/debounce).

5. **LAN multiplayer smoke (`Godot/Nexus/MultiplayerManager.gd`)**
   - Scope: validate one host/join path on current branch.
   - Acceptance:
     - Document exact host/join steps in this file after test.
     - Record pass/fail + blocker note (NAT, IP, scene sync, etc.).

### Known friction (re-check after merges)

T-pose / **AnimationTree**, vision **SubViewport** paths, cockpit grab/layout, double-trigger pinch — see prior context logs; not always backend regressions.

### Ops Web UI cross-links for VR dev

- **FEATURE MAP** tab = living view of **`FEATURE_INVENTORY.md`** (tiers + stubs).
- **Chatterbox** tab = browser iframe; on Quest, Chatterbox is **not** embedded in Godot the same way — copy in `WebUI.gd` points users to **PC Web UI :8080** when needed.

---

## Host paths (Windows)

`.env` next to `docker-compose.yml`:

- **`LUMAX_MODELS_ROOT`** — e.g. `D:/Lumax/models` (see compose comments for Docker Desktop vs WSL).
- **`LUMAX_INVOKEAI_MODELS_HOST`** — real InvokeAI `models` dir (optional CSV merge).

---

## Git / secrets hygiene

**Never commit:** `.env`, live HA `.storage/` / `secrets.yaml`, DB, logs, `Backend/tailscale/state/` — see root **`.gitignore`**.

**Often local-only:** full `Frontend/Body/Mobile/`, some `scripts/*.ps1`, Android exports — reconcile before merging to `main`.

---

## Suggested order of work (Web + VR)

1. **Web:** Sign in → **IMAGINE** smoke → **CHATTERBOX** tab if using Resemble → **`run_all_tests.ps1`** green.  
2. **VR:** Align ribbon + config fetch with `lumax_ui_config.json` → test soul connectivity → Quest/LAN when ready.  
3. Commit tracked helpers (`scripts/`, `tests/`, compose) when stable.

---

## Automation playbook (Cursor)

For background feature churn with quality gates, use:

- `AGENT_AUTOMATION_WORKFLOW.md` — Feature Map-driven queue, safety gates, execution loop, prompt templates.
- Pair with Web UI **FEATURE MAP** filters (Godot + Tier C first).

---

*Update this file when default TTS stack, creativity paths, Godot entry/wiring, or Feature Map / inventory workflows change.*
