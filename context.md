## Ingress instruct

Method references: [context_logmaster_merge.md](context_logmaster_merge.md) and [Methodology.md](Methodology.md).

# LUMAX: CORE DIRECTIVES & ARCHITECTURE

## 1. Project Overview
- **Lumax** is an immersive companion project integrating **several frontends** (starting with Godot VR) with a modular, local-first Python backend hosted via Docker.

## 2. Technical Architecture
### Frontends (Multi-platform)
- **Primary Focus:** Godot 4.2+ (VR) at `code/godot/vrcompagent/`.
- **Planned:** Modular architecture designed to support multiple frontends connecting to the same backend "Brain".
- **Tech Stack (VR):** OpenXR, Godot XR Tools, VRM models.

### Backend (Dockerized Python)
- **Logic Service (Port 8000):** FastAPI/LangChain at `code/langchain/compagent.py`.
- **STT Service (Port 8001):** Faster-Whisper.
- **TTS Service (Port 8002):** Kokoro.
- **LLM Strategy:** Prefer Ollama (Local) via `qwen3-vl`. Use Gemini 3 (Cloud) when requested.

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

Human session history (this file) pairs with in-engine logging: see [context_logmaster_merge.md](context_logmaster_merge.md) for `LogMaster`, `lumax_diagnostic.log`, and `godot.log`.

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

