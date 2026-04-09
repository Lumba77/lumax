# LUMAX handoff (next session)

## Architecture (Docker “triple unification”)
Single `lumax_unified` image (NVIDIA/CUDA) with shared `. -> /app` mount on `lumax_local`:

| Service | Ports | Role |
|--------|-------|------|
| `lumax_soul` | 8000 | Cognitive core (FastAPI / compagent) |
| `lumax_body` | 8001–8002 | Ears (STT) + Mouth (TTS), one container |
| `lumax_ops` | 8080 / 8006 | Web UI + sentry utilities |
| `lumax_turbochat` | 8005 | XTTS / turbo speech |
| `lumax_ollama_backup` | 11434 | In-stack Ollama; blobs under `LUMAX_MODELS_ROOT/Ollama` |

Default in-stack Ollama: `OLLAMA_HOST=http://lumax_ollama_backup:11434` unless overridden (e.g. Windows host Ollama via `host.docker.internal`).

## Repository layout (current)
- **`Backend/`** — Python services (Body, Mind/Cognition, Creativity, etc.).
- **`Godot/`** — Godot 4.x VR project (export from `Godot/` as project root).
- **`Frontend/Body/Webui/`** — FastAPI web UI + `lumax_ui_config.json` / branding JSON served to Godot and browsers.
- **`ops/playbooks/`** — Sentry/watchdog policy JSON (container path `/app/ops/playbooks/...`).
- **`scripts/`** — Automation (preflight, watchdog, sync, etc.).
- **`tests/`** — Ad-hoc test scripts (e.g. STT/TTS helpers).
- **`div/files/`** — Local scratch only (gitignored): logs, old Godot binaries, moved root clutter. **Do not treat as product source.**

## Host data paths (Windows)
Models and large blobs live on **D:** — use **`.env`** next to `docker-compose.yml`:

- `LUMAX_MODELS_ROOT` → e.g. `D:/Lumax/models` (compose fallbacks also use `/d/Lumax/models` style defaults).
- Piper / Turbo dirs: `LUMAX_PIPER_MODEL_DIR`, `LUMAX_TURBO_MODEL_DIR` as documented in `docker-compose.yml` comments.

## Git / GitHub
- **Default branch:** `main` on `https://github.com/Lumba77/lumax`.
- Recent themes: gitignore hygiene (no `__pycache__` / nested `.env` / Redis dumps in repo), Godot LAN + `nat_peer` sync (`Synapse.gd` / `MultiplayerManager.gd`), compose defaults for D: `Lumax`, large WIP commit (backend, Webui, ops, scripts, tests), then **Chosen** animations + **addons** sync commit.
- **Secrets:** never commit `.env` or `Backend/Mind/Cognition/.env`; patterns in root `.gitignore`.

## Godot / Quest networking
- **PC / editor:** Soul defaults to `http://127.0.0.1:8000` (`/health` for smoke tests).
- **Quest (Wi‑Fi):** run `.\connect_quest.ps1` to write **`Godot/lumax_network_config.json`** (gitignored) with PC LAN IP; or rely on **LAN auto-discover** in `Synapse.gd` (`quest_lan_auto_discover`, plus `user://lumax_soul_host.txt` after first find). **USB + adb:** `.\connect_quest.ps1 --adb` sets port reverse and `soul_host=127.0.0.1` on device.
- **VRM:** avatar assets live under **`Godot/vrm/`** (not `Godot/Body/Models/` for current Jen pipeline).

## Godot editor binaries (local)
- **Godot 4.6.2** (stable) EXEs are under **`div/files/godot/`** (not repo root), e.g. `Godot_v4.6.2-stable_win64.exe` — update shortcuts if you open the editor from Explorer.
- **Godot 4.2.2** console binary was removed from the tree (obsolete).

## Known friction (carry forward)
1. **T-pose / animation:** Jen can still hit pose starvation; check AnimationTree vs VRM / idle pool.
2. **Vision cockpit previews:** Empty previews may be wrong SubViewport paths in `SkeletonKey.gd` vs `Lumax_Core.tscn`.
3. **UI grab / “double crossed” panel:** Possible basis conflict in cockpit grab logic.
4. **Keyboard / layout:** Bottom row clipping if cockpit height exceeds viewport budget.

## Suggested next steps
1. Re-verify **T-pose** and **vision** paths against current scenes.
2. Run **`docker compose up`** and **`http://127.0.0.1:8000/health`** before deep Godot debugging.
3. Keep **`HANDOFF.md`** / **`context.md`** updated when architecture or paths shift.
