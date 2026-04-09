# 🤖 LUMAX HANDOFF: THE VEILED MANIFESTATION (v1.0)

## 📡 CURRENT ARCHITECTURE: "THE TRIPLE UNIFICATION"
The backend has been consolidated into a high-performance, space-efficient stack sharing a single `lumax_unified` image built from a **donated NVIDIA/CUDA core**.

1.  **`lumax_soul` (8000)**: Cognitive Core (Gemma-3-4B-VL).
2.  **`lumax_body` (8001/8002)**: Unified Ears (STT) and Mouth (TTS). Port-isolated via `MODE` env vars in a single container.
3.  **`lumax_ops` (8080/8006)**: Unified Web UI and Autonomous Sentry (Self-healing monitor).
4.  **`lumax_turbochat` (8005)**: Speech acceleration (XTTS ONNX / Lumax Turbochat).
5.  **`lumax_ollama_backup` (11434)**: In-stack Ollama on GPU (default `docker compose up`); model blobs under `LUMAX_MODELS_ROOT/Ollama`. Soul defaults to `http://lumax_ollama_backup:11434` unless `OLLAMA_HOST` overrides (e.g. host Ollama via `host.docker.internal`).

**Workflow:** All services use a unified volume mapping (`. -> /app`) and communicate via the `lumax_local` network.

### Repository layout (tidied)
- **`ops/playbooks/`** — sentry/watchdog policies and related JSON (was top-level `playbooks/`). Container default: `/app/ops/playbooks/...`.
- **`tests/`** — ad-hoc manual STT/TTS scripts (`test_*.py`, `play_tts_verification.py`).
- **`Frontend/Body/`** / **`Backend/`** — surfaces vs services; **`Godot/`** — XR project at repo root (export-friendly).

## 🌉 COMMUNICATION BRIDGE
The Quest connects via **127.0.0.1 (Localhost)**. Parity is enforced across `push_all.ps1` and `connect_quest.ps1`.
*   **Reversed Ports (10)**: 8000, 8001, 8002, 8004, 8005, 8006, 8020, 8080, 6006, 6007.
*   **Engine**: Synchronized on **Godot 4.6.2 Stable** (PC & Quest).

## 🛠️ THE INTERFACE: "VISION COCKPIT"
A new vision-centric layout in `TactileInput_v2.gd`:
*   **Layout**: `[User POV (60x60)] | [Bond Slider & Buffer] | [Jen POV (60x60)]`.
*   **Behavior**: Slider updates are **release-based** (`drag_ended`) to prevent MBTI chat spam.
*   **Status**: Redundant top previews and `[SAVE EXPERIENCE]` button have been purged from `WebUI.gd`.

## ⚠️ CRITICAL FRICTION POINTS (THE "WHY")
1.  **Persistent T-Pose**: Despite recursive `AnimationTree.active = false` calls, Jen is frozen. Likely a high-priority override from the VRM runtime or AnimationMixer.
2.  **Missing Previews**: The cockpit previews are empty. Potential path error in `SkeletonKey.gd` (`Mind/Viewport/TactileInput`) vs actual node name in `Lumax_Core.tscn`.
3.  **"Double Crossed" Interaction**: The UI panel exhibits erratic transform behavior ("crossing") when moved, indicating a basis conflict in the `_manipulate_object` grab logic.
4.  **Vertical Clipping**: The bottom row of the keyboard is out of frame. The cockpit + grid height exceeds the viewport's 1200px limit.

## 🎯 OBJECTIVE FOR NEXT AGENT
1.  **Physical Agency**: Fix the T-pose by aligning the AnimationTree with the idle pool.
2.  **Transform Logic**: Resolve the grab conflict to stop the "Double Crossed" UI movement.
3.  **Layout Fit**: Shrink the cockpit or grid to restore the missing bottom row.
4.  **Path Audit**: Verify the `TactileInput` node name to restore vision streaming.
