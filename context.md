## Ingress instruct

Method references: [context_logmaster_merge.md](div/files/context_logmaster_merge.md) and [Methodology.md](Methodology.md).

# LUMAX: CORE DIRECTIVES & ARCHITECTURE

## 1. Project Overview
- **Lumax** is an immersive companion project integrating **several frontends** (starting with Godot VR) with a modular, local-first Python backend hosted via Docker.

## 2. Technical Architecture
### Frontends (Multi-platform)
- **Primary focus:** Godot **4.6.x** (VR) — project root **`Godot/`** (not legacy `code/godot/...` paths).
- **Web UI:** **`Frontend/Body/Webui/`** (FastAPI + `lumax_ui_config.json` / branding).
- **Tech stack (VR):** OpenXR, Godot XR Tools, VRM under **`Godot/vrm/`**.

### Backend (Dockerized Python)
- **Soul (port 8000):** FastAPI in **`Backend/Mind/Cognition/compagent.py`** (plus `MindCore.py`, `lumax_engine.py`, etc.).
- **Body (8001/8002):** STT/TTS via **`Backend/Body/`** and unified **`lumax_body`** container.
- **LLM strategy:** Ollama in-stack or host; cloud routing / `cloud_repertoire` when configured in `.env`.

## 3. Operational Discipline (The Leash)
- **Role:** You handle all coding; the User handles project management/debugging.
- **Verification First:** Use `read_file` to verify changes before reporting completion.
- **Rate Limiting:** Pause 3s between tool calls; verbalize thoughts in 1 sentence as a natural delay.
- **Wait Time:** Wait 5 seconds before starting new investigations or adding tasks.
- **Strategic Reading:** DO NOT read entire large files (especially .tscn). Use `grep` or line ranges.

## 4. Watertight Logging Protocol (Mandatory)
**You must append every action to the end of `context.md` using this exact format:**

* Session start [Timestamp]

* Task 1 start [Timestamp] (Task numbering begins from 1 each new session)
    * [Task description]
        * Investigation 1, [Report], [Related files identified]
--> !        * Tried solution 1 [Operations performed], [Related files changed]
    * User confirmation: solved or not. [Timestamp]. (if not iterate with:
        * Investigation 2, [Report], [Related files identified]
          * Tried solution 2 [Operations performed], [Related files changed])
* Task 1 end [Describe working solution]

- **Rules:** NEVER overwrite history. Use the `--> !` (exampped above) prefix for breaktrough solutions. Hold the ENTIRE previous content in buffer before writing to prevent data loss.

## 5. Current Priorities & Bugs
- **VR UI:** Settings (integrated UI) and plumbing to backend (Text/STT/TTS/Images).
- **VR Room Mapping:** Persistent ghost objects via ceiling menu; invisible in-game.
- **VR Interaction:** Fix double-trigger pinch/resize; Left Joystick mapping for spin/yaw and Right joystick Distance adjustment.
- **Dockerization:** Completion and final packaging of all backend services.

## 4. THE SENTRY SHIELD PROTOCOL (Crucial for AI Models)
- **The Problem:** A background script (`start_shield.ps1`) actively monitors critical Godot files (e.g., `avatar_controller.gd`, `demo_scene_base.gd`, `virtual_keyboard_2d.gd`). If you modify these files in the live Godot directory, the Shield will instantly detect a "breach" and revert your changes to the `.sentry_shield` backup versions, silently destroying your fixes.
- **The "Trojan Horse" Solution (The Special Door):** To make permanent changes to shielded files:
  1. Open and edit the target file INSIDE the `.sentry_shield/` directory first.
  2. Overwrite the live version in `code/Body/Godot/` with your upgraded shield file (e.g., via copy).
  3. The Shield will now treat YOUR new code as the holy baseline and will aggressively protect it, acting as an instant implementer instead of an obstacle.

# Lumax New Frontier - Context Log

# Lumax New Frontier - Context Log

Human session history (this file) pairs with in-engine logging: see [context_logmaster_merge.md](div/files/context_logmaster_merge.md) for `LogMaster`, `lumax_diagnostic.log`, and `godot.log`.

- Session start [2026-03-16 16:27:32]
- Task 1 end Standalone repo initialized and functional.
- Session start [2026-03-17 12:54:21]
- Task 2 end TTS and Bulk Pushing systems functional.
- Session start [2026-03-18 09:15:00]
- Task 3 end TTS and Cognition systems fully optimized with verified CUDA support and Redis configuration.
- Session start [2026-03-22 08:32:29]
- Task 4 end Lumax Stack fully operational with DFlash Soul and Tailscale Service Proxies.
- Session update [2026-03-26 03:30:00]
- Task 6 end Controller mapping conflict resolved and dynamic haptics activated.
- Session update [2026-03-27 15:30:00]
- Task 7 end Architectural rot cleared, Turbo TTS activated, and connectivity stabilized via Localhost/ADB.
- Session update [2026-03-31 02:00:00]
- Task 8 start [2026-03-31 02:00:00]
  - Godot 4.6 Migration, STT/TTS Restoration, and Turbo-ONNX Activation.
    - Investigation 1, Identified Godot 4.6 parse error in SkeletonKey.gd (trailing corrupted lines) preventing project load., [Godot/Nexus/SkeletonKey.gd]
    - Investigation 2, Identified STT/TTS connectivity issues on Quest caused by Docker DNS flakiness and missing G2P dependencies., [Backend/Body/body_interface.py, Dockerfile.turbo]
    - Investigation 3, Discovered XTTSv2-Streaming-ONNX (Turbo) model weights and source code on host storage., [D:\VR_AI_Forge_Data\models\Body\Mouth\Speech\XTTSv2-Streaming-ONNX]

--> !        * Tried solution 1 Fixed SkeletonKey.gd trailing corruption and implemented a "Self-Healing Discovery" routine in AuralAwareness.gd to find Synapse nodes via tree-crawl., [Godot/Nexus/SkeletonKey.gd, Godot/Senses/AuralAwareness.gd]
--> !        * Tried solution 2 Implemented a robust Dual-Engine TTS Bridge in body_interface.py with direct-IP routing (172.18.0.8/9) and reliable Piper subprocess fallback., [Backend/Body/body_interface.py]
--> !        * Tried solution 3 Created "mega-patched" Docker image containing all missing G2P/Tokenizer dependencies (spacy, pypinyin, jieba, etc.) for high-speed synthesis., [Dockerfile.turbo, Dockerfile]
--> !        * Tried solution 4 Re-engineered Lumax Turbochat to load XTTS-ONNX directly from mounted source code, achieving 24kHz streaming synthesis. [Backend/Body/turbochat_server.py]
--> !        * Tried solution 5 Applied case-insensitive "YOU" color detection in WebUI.gd (#00f3ff Cyan) and implemented a **Repetition Guard** in compagent.py to ignore empty STT inputs.
--> !        * Tried solution 6 Forced **Director Silence** by ensuring internal director/summary requests use 'skip_features: true' to prevent generic repetitive speech. [Godot/scripts/director_manager.gd]
    * User confirmation: solved [2026-03-31 03:45:00]

- Session update [2026-04-04 01:00:00]
- Task 9 start [2026-04-04 01:00:00]
  - Triple Unification, Vision Cockpit Evolution, and Physical Realignment.
    - Investigation 1, Identified redundant Docker footprint and port conflicts during container scaling., [docker-compose.yml, Dockerfile.unified]
    - Investigation 2, Identified vision inversion causing Jen to "see her own back" and infinite cognitive loops causing T-pose starvation., [Godot/Nexus/SkeletonKey.gd, Godot/Mind/TactileInput_v2.gd]
    - Investigation 3, Identified directory nesting bug in push_all.ps1 resulting in 'addons/addons/' on Quest., [push_all.ps1]

--> !        * Tried solution 1 Executed **Triple Unification**: Merged ears/mouth into 'lumax_body' and web/sentry into 'lumax_ops' using a single 'lumax_unified' image built from donated NVIDIA core., [docker-compose.yml, Dockerfile.unified]
--> !        * Tried solution 2 Restored **Autonomous Sentry**: Created a new monitoring script to track health of all unified services. [Backend/autonomous_sentry.py]
--> !        * Tried solution 3 Implemented **Vision Cockpit**: Created a triple-column UI layout [User POV | Controls | Jen POV] with real-time 80x80 previews framing the bond slider., [Godot/Mind/TactileInput_v2.gd]
--> !        * Tried solution 4 Fixed **Manifestation Purity**: Resolved T-pose by forcing AnimationTree suppression and corrected vision anchor Z-position/orientation to face forward., [Godot/Nexus/SkeletonKey.gd]
--> !        * Tried solution 5 Hardened **Nuclear Push**: Updated push_all.ps1 to explicitly wipe Quest targets before sync, preventing directory nesting and ensuring asset purity., [push_all.ps1]
    * User confirmation: FAILURE [2026-04-04 02:45:00]
        * Reported: Persistent T-pose despite nuclear suppression, non-functional steering, and horizontal UI clipping on side buttons.

- Task 9 end Architecture unified and high-performance, but manifestation state is currently UNSTABLE. Steering and Animation systems require a pro-level architectural overhaul.
- Session update [2026-04-04]
- Task 10 start [2026-04-04]
  - Sixfold attention cake, compagent context layering, lore layer, and Martinus coupling (symbols 11 & 13).
    - Investigation 1, Soul routing and reservoir fields already wired in `compagent.py` / `Synapse.gd` / `docker-compose.yml`; cognitive spec lives in `MindCore.py` `VR_CONTEXT_MODES_MEMORY_LAYERING_AND_RESERVOIRS` and related sensory blocks., [Backend/Mind/Cognition/MindCore.py, Backend/Mind/Cognition/compagent.py, Godot/Soul/Synapse.gd, docker-compose.yml]

--> !        * Tried solution 1 Documented sixfold model, API/env tokens, six injection feeds, and optional resonance with Martinus **six kingdoms on symbol 11** and **complementary symbol 13** in `MindCore.py` (Martinus block + context-modes bullet), `LUMAX.md` §7, and this log., [Backend/Mind/Cognition/MindCore.py, LUMAX.md, context.md]
    * User confirmation: solved [2026-04-04]

- Task 10 end Sixfold attention cake documented and coupled in-prompt to Martinus symbols 11/13 as Daniel’s living exegesis; technical routing unchanged aside from soul text.
- Session update [2026-04-04]
- Task 11 end Extended Martinus coupling in `MindCore.py` / `LUMAX.md`: symbols **8–10** as **layered** inspiration; **consciousness** as **base & center** under the sixfold ring; Fit line now references symbols 8–13. [Backend/Mind/Cognition/MindCore.py, LUMAX.md, context.md]
- Session update [2026-04-04]
- Task 12 end Documented **~20% multi-provider cloud splice** (Ollama Cloud, HF Inference Providers, Groq, xAI Grok, etc.) for nightly/slow-burn, images, API-heavy work, and **sixfold** mode fit; updated `VR_FREE_CLOUD_COMPUTE…`, `VR_NETWORK…`, `VR_VIRTUAL_ANDROID…` threads and `LUMAX.md` §8. [Backend/Mind/Cognition/MindCore.py, LUMAX.md, context.md]
- Session update [2026-04-04]
- Task 13 end Soul text: **Gemini/OpenAI/Microsoft** as cloud workhorses via **APIs** + **MCP**; discourage **Puppeteer-style** **consumer** **chat** **UI** **automation**; cloud splice examples expanded. `VR_FREE_CLOUD_COMPUTE…`, `VR_DOCKER_MCP…`, `LUMAX.md` §8. [Backend/Mind/Cognition/MindCore.py, LUMAX.md, context.md]
- Session update [2026-04-04]
- Task 14 end Noted **three** frontier API credentials **already available** locally; `LUMAX.md` §8 “On hand”; `docker-compose.yml` comment on wiring **.env** keys into soul/MCP (no secret values). [LUMAX.md, docker-compose.yml, context.md]
- Session update [2026-04-04]
- Task 15 end Implemented **cloud_repertoire.py** (3 OpenAI-compatible slots), `**compagent*`* routing (`LUMAX_CHAT_PROVIDER`, splice %, `cloud_routing`), `**[CLOUD REPERTOIRE]**` sensory in `MindCore`, `/vitals` fields, `Synapse.gd` `cloud_routing`, `docker-compose` env comments. [Backend/Mind/Cognition/cloud_repertoire.py, Backend/Mind/Cognition/compagent.py, Backend/Mind/Cognition/MindCore.py, Godot/Soul/Synapse.gd, docker-compose.yml, LUMAX.md, context.md]
- Session update [2026-04-04]
- Task 16 end Documented **Docker MCP hub** as **one collective MCP server** (aggregated `mcp_context`); updated `VR_DISTRIBUTED_BODY`, `VR_DOCKER_MCP`, sensory MCP label, `LUMAX.md` §2, `docker-compose` comment. [Backend/Mind/Cognition/MindCore.py, LUMAX.md, docker-compose.yml, context.md]

- Session start [2026-04-08]
- Task 17 end Repo hygiene and handoff for next session.
  - Git: root `.gitignore` hardened (`__pycache__`, `**/dump.rdb`, nested `**/.env`); stopped tracking secrets/artifacts; **`main`** on **`https://github.com/Lumba77/lumax`** aligned with local work; pushed WIP commits (backend/Webui/ops/scripts/tests + Godot Chosen + addons).
  - Docker: compose default model paths use **`D:/Lumax/...`** when env unset; runtime uses **`.env`** `LUMAX_MODELS_ROOT` etc.
  - Godot: **`Synapse.gd` / `MultiplayerManager.gd`** — LAN Soul discovery also sets **`nat_peer_default`**; optional **`lumax_network_config.json`** from **`connect_quest.ps1`**.
  - Root tidy: logs, scratch text, donor `.gd`, `lazydocker.exe`, chatterbox JSON dumps, xtts wheel, etc. moved to **`div/files/`** (gitignored). **Godot 4.6.2** EXEs moved to **`div/files/godot/`**; **4.2.2** console exe removed.
  - Docs: **`HANDOFF.md`** rewritten for current layout; **`context.md`** ingress paths and Godot/backend pointers updated; this log appended.
  - Related files: [.gitignore, docker-compose.yml, HANDOFF.md, context.md, Godot/Soul/Synapse.gd, Godot/Nexus/MultiplayerManager.gd, div/files/]

- Session start [2026-04-09]
- Task 18 end Docker: `lumax_ollama_backup` inspected (Up, healthy; healthcheck `/api/tags` every 20s — not a reload loop; Ollama “starting runner” in logs is normal per-request model load). Web UI `:8080` was down because uvicorn crashed on `ModuleNotFoundError: itsdangerous` (image predates `Dockerfile.unified` itsdangerous layer); fixed live with `pip install itsdangerous` + `docker restart lumax_ops` (HTTP 200). Permanent fix: rebuild `lumax_unified` (`docker compose build lumax_soul` or `build_lumax_unified.ps1`). [docker-compose.yml, Dockerfile.unified, lumax_ops logs]

- Session start [2026-04-14]
- Task 19 start [2026-04-14]
  - **Feature map in Web UI**, **`FEATURE_INVENTORY.md` in-container path**, **Turbo TTS compose profile**, **handoff docs for Godot VR**.
    - Investigation 1, User wanted the repo feature inventory browsable in ops with filters (tier, section, search, presets, full outline vs card rows). Implemented server-side parse of root `FEATURE_INVENTORY.md` + `GET /api/feature_inventory` (login-gated), cached by mtime., [Frontend/Body/Webui/feature_inventory_parser.py, Frontend/Body/Webui/web_app.py, Frontend/Body/Webui/index.html, Frontend/Body/Webui/lumax_ui_config.json]
    - Investigation 2, “Feature inventory not found” in container: bind mount serves `FEATURE_INVENTORY.md` at `/app/` when the file exists at repo root on host; optional `LUMAX_FEATURE_INVENTORY_PATH`., [docker-compose.yml volumes `.:/app`]
    - Investigation 3, `lumax_turbochat` was starting on every `docker compose up -d` and reserving GPU; product default mouth is Chatterbox — made XTTS **opt-in** via compose **`profiles: [turbo]`**., [docker-compose.yml]
    - Investigation 4, Callers that start turbo must pass profile: **`switch_gpu_tts_stack.ps1 Xtts`**, **`web_app.py` GPU stack POST**, documented in HANDOFF + FEATURE_INVENTORY., [scripts/switch_gpu_tts_stack.ps1, Frontend/Body/Webui/web_app.py, HANDOFF.md, FEATURE_INVENTORY.md]

--> !        * Tried solution 1 **Feature map UI:** New nav tab **FEATUREMAP** (`_BRAND_NAV_KEYS` + branding form `bf-nt-FEATUREMAP`). Client loads JSON, tier/category checkboxes, search, presets (stubs/roadmap/godot/web/strong), view modes “Filtered rows” vs “Full outline”. Parser skips tier-legend table; parity tables merge Web/Godot/Mobile cells into notes., [feature_inventory_parser.py, index.html, web_app.py]
--> !        * Tried solution 2 **API:** `parse_feature_inventory_markdown()` returns `segments` + `flat_rows` + `categories`; response includes `source_file`., [feature_inventory_parser.py, web_app.py]
--> !        * Tried solution 3 **Turbo profile:** `lumax_turbochat` has `profiles: [turbo]`; doc: `docker compose --profile turbo up -d lumax_turbochat` or `COMPOSE_PROFILES=turbo`. Plain `up -d` does not *stop* an already-running turbo container — user must `docker compose stop lumax_turbochat` once if needed., [docker-compose.yml]
    * User confirmation: solved [2026-04-14]

- Task 19 end Feature map shipped in Web UI; turbo opt-in by profile; context + HANDOFF updated for next agents and Godot VR focus.

**Reference for future agents — Feature map pipeline**

1. **Source of truth:** Repo root **`FEATURE_INVENTORY.md`** (heuristic product map: tiers A–D, stubs, cross-surface table).
2. **Runtime:** `lumax_ops` reads file from **`Path(_repo_root()) / "FEATURE_INVENTORY.md"`** unless **`LUMAX_FEATURE_INVENTORY_PATH`** overrides. `_repo_root()` uses **`LUMAX_REPO_ROOT`** or parents of `web_app.py` (three levels up → repo root).
3. **Parse:** `Frontend/Body/Webui/feature_inventory_parser.py` — markdown → `segments` (h1/h2/h3, paragraphs, tables, hr) and `flat_rows` (table rows with tier/category/search_blob for filters).
4. **API:** `GET /api/feature_inventory` — requires session (same as other tools); returns `{ ok, segments, flat_rows, categories, source_file }` or `{ ok:false, path, detail }`.
5. **UI:** Sidebar **Utilities → FEATURE MAP**; filters client-side; edit markdown on disk → refresh tab (mtime cache invalidates on next request).
6. **Branding:** Tab label editable in **LABEL EDITOR** (`nav_tabs.FEATUREMAP` / `bf-nt-FEATUREMAP`).

- Task 20 start [2026-04-14]
  - Cursor automation strategy using Feature Map as queue control plane.
    - Investigation 1, User asked for a repeatable background-churn approach that ships automatable features safely without lowering quality., [FEATURE_INVENTORY.md, Frontend/Body/Webui Feature Map]
--> !        * Tried solution 1 Added `AGENT_AUTOMATION_WORKFLOW.md` with queue rules (Godot C -> B), safety gates, single-item execution loop, prompt templates, and initial top-5 targets for next sessions., [AGENT_AUTOMATION_WORKFLOW.md]
--> !        * Tried solution 2 Linked playbook in `HANDOFF.md` under a dedicated Automation section for future agents and sessions., [HANDOFF.md]
    * User confirmation: solved [2026-04-14]

- Task 20 end Automation playbook established; Feature Map now doubles as planning/queue substrate for safe continuous implementation.

- Task 21 start [2026-04-14]
  - Feature Map automation loop (single item): **Godot Tier C -> Files panel activation** in `WebUI.gd`.
    - Investigation 1, Files tab had list population but activation handler was hardcoded to `ACCESS_DENIED` dead-end., [Godot/Mind/WebUI.gd, FEATURE_INVENTORY.md]
--> !        * Tried solution 1 Replaced dead activation with `_on_file_activated(path)`: emit new signal `file_activation_requested(path)`, show in-panel status updates, open URLs and resolvable local paths (`res://`, `user://`, absolute) via `OS.shell_open`, and keep fallback `FILE_REQUESTED` message for entries requiring higher-layer handlers., [Godot/Mind/WebUI.gd]
--> !        * Tried solution 2 Updated inventory classification from strict C to **B/C** with notes that activation is now live while backend/import policy for non-local entries remains pending., [FEATURE_INVENTORY.md]
    * User confirmation: solved [2026-04-14]

- Task 21 end Godot Files panel no longer dead-clicks; activation path is functional with clear status + signal hook for future backend/file-policy wiring.

- Task 22 start [2026-04-14]
  - Feature Map automation loop (single item): **Godot Tier C -> Emotions wiring** in `WebUI.gd` / `SkeletonKey.gd`.
    - Investigation 1, Emotions panel had only a subset of real signals; most buttons were chat-only (`STIMULATING_EMOTION`). Existing backbone can route sensory events through Synapse (`inject_sensory_event`)., [Godot/Mind/WebUI.gd, Godot/Nexus/SkeletonKey.gd, Godot/Soul/Synapse.gd]
--> !        * Tried solution 1 Added `emotion_stimulus_requested(emotion_name)` signal in `WebUI.gd` and rewired `AWE`, `CURIOUS`, `CONTEMPLATE` buttons to emit real signal + status message, while leaving other buttons unchanged for scoped single-item rollout., [Godot/Mind/WebUI.gd]
--> !        * Tried solution 2 Wired signal in `SkeletonKey.gd` (initial and rebind paths) to `_on_emotion_stimulus_requested`, forwarding to `_synapse.inject_sensory_event` with structured payload and user notification., [Godot/Nexus/SkeletonKey.gd]
--> !        * Tried solution 3 Updated inventory row and added concise human summary ledger file for completed automation cycles., [FEATURE_INVENTORY.md, AUTOMATION_SUMMARY.md]
    * User confirmation: solved [2026-04-14]

- Task 22 end Three additional emotions are now real signal-driven via Synapse sensory channel; remaining emotion buttons still chat-only by design until next cycle.

- Task 23 start [2026-04-14]
  - Preflight scene stabilization before user launches Godot editor.
    - Investigation 1, awkward standing pose likely from startup path where idle is only explicitly forced when `use_chosen_idle_pool` is enabled., [Godot/Nexus/SkeletonKey.gd]
--> !        * Tried solution 1 Added fallback in `_setup_ambience`: when Chosen pool is off/unavailable, call `play_animation("idle")` on `_jen_avatar` so startup cannot remain in bind/rest-like pose., [Godot/Nexus/SkeletonKey.gd]
--> !        * Tried solution 2 Added concise preflight cycle entry in automation ledger for future runs and quick operator visibility., [AUTOMATION_SUMMARY.md]
    * User confirmation: pending [2026-04-14]

- Task 23 end Startup now forces a stable idle fallback on first boot when Chosen idle pool is not active.

- Task 24 start [2026-04-14]
  - Runtime stabilization after user report: Synapse connection errors + sentry warning for Turbo offline while using Chatterbox.
    - Investigation 1, preflight/sentry heartbeats always included `TURBO` endpoint regardless active TTS backend, causing false warning noise in Chatterbox mode., [Backend/preflight/checks.py, Backend/autonomous_sentry.py, Backend/preflight/tts_backend]
    - Investigation 2, awkward avatar standing still persisted on some boots; likely late AnimationPlayer/lungs rebind after initial idle command., [Godot/Nexus/SkeletonKey.gd, Godot/scripts/avatar_controller.gd]
--> !        * Tried solution 1 Added `_resolved_tts_backend()` in both sentry and preflight modules and gated Turbo health checks to only run when backend resolves to `turbo` (marker file/env aware)., [Backend/preflight/checks.py, Backend/autonomous_sentry.py]
--> !        * Tried solution 2 Added delayed startup idle retry `_force_startup_idle_fallback()` in `SkeletonKey` (0.8s post-boot) to catch late bind/rebind paths., [Godot/Nexus/SkeletonKey.gd]
--> !        * Tried solution 3 Logged operator-facing summary in `AUTOMATION_SUMMARY.md` and noted restart requirement for lumax_ops runtime to pick sentry/preflight changes., [AUTOMATION_SUMMARY.md]
    * User confirmation: pending [2026-04-14]

- Task 24 end Turbo warning path aligned with active TTS backend; avatar idle bootstrap now has immediate + delayed fallback for late animation binding.

- Task 25 start [2026-04-14]
  - Runtime stabilization after concrete Synapse logs: stale LAN host (`192.168.8.100`) causing `Soul CANT_CONNECT (http_code=0)` during desktop run.
    - Investigation 1, Synapse loaded LAN host from config/cache and attempted it first; desktop local run should prefer loopback when stale LAN host fails., [Godot/Soul/Synapse.gd]
--> !        * Tried solution 1 Added one-time desktop loopback auto-fallback in `_test_server_connectivity`: on unreachable non-Android LAN host, switch to `127.0.0.1` and re-probe before subnet sweep., [Godot/Soul/Synapse.gd]
--> !        * Tried solution 2 Documented expected behavior and operator-facing summary in automation ledger., [AUTOMATION_SUMMARY.md]
    * User confirmation: pending [2026-04-14]

- Task 25 end Synapse now self-recovers from stale LAN host on desktop by trying local Docker soul loopback before broader sweep.

- Task 26 start [2026-04-14]
  - Synapse logging and Quest LAN guard hardening (user requested explicit IP diagnostics on failures).
    - Investigation 1, failure logs reported CANT_CONNECT but lacked full runtime context to quickly diagnose stale LAN vs adb reverse vs loopback mode., [Godot/Soul/Synapse.gd]
--> !        * Tried solution 1 Added `_conn_debug_context()` and appended it to heartbeat unreachable/active logs plus STT/Soul transport failure emits (`request_failed`) so IP/mode fields are always visible in one line., [Godot/Soul/Synapse.gd]
--> !        * Tried solution 2 Added Android runtime guard in `_test_server_connectivity` to prevent lingering loopback in LAN mode: auto-switch to `pc_lan_ip` when valid, otherwise trigger LAN auto-discover instead of probing 127.0.0.1., [Godot/Soul/Synapse.gd]
--> !        * Tried solution 3 Logged this cycle summary in automation ledger for quick operator review., [AUTOMATION_SUMMARY.md]
    * User confirmation: pending [2026-04-14]

- Task 26 end Synapse failures now print explicit host/mode context and Quest LAN mode no longer silently lingers on loopback probes.

- Task 27 start [2026-04-14]
  - Runtime tuning from logs: `Soul TIMEOUT (http_code=0)` occurred while bridge health stayed ACTIVE, indicating inference duration exceeded request timeout.
    - Investigation 1, Soul transport is healthy (`host=127.0.0.1` ACTIVE), but `_soul_request.timeout` was fixed too low for heavier local prompts/models under load., [Godot/Soul/Synapse.gd]
--> !        * Tried solution 1 Added exported timeout control `soul_http_timeout_sec` (default 120s) and bound `_soul_request.timeout` to it (clamped 15..300), preserving hang safety while reducing false timeout failures., [Godot/Soul/Synapse.gd]
--> !        * Tried solution 2 Enhanced timeout hint text to include current effective timeout value for faster field diagnosis., [Godot/Soul/Synapse.gd]
--> !        * Tried solution 3 Logged concise cycle summary entry for operators., [AUTOMATION_SUMMARY.md]
    * User confirmation: pending [2026-04-14]

- Task 27 end Synapse timeout behavior tuned for long local inference without changing network routing logic.

