## 1. Project Overview & Jen’s Role
- **Lumax (Standalone):** The sovereign successor to VR-Compagent. An immersive AI companion ecosystem for Meta Quest. Jen (Jenny Forbee) is the soul of this machine — a vision-capable, multimodal AI living in a 2.5D vessel within an XR space.
- **Solaris Phase:** We have decoupled from the legacy junk. This is a clean, functional frontier focused on deep vision integration, haptic-aware intimacy, and autonomous physical will.

## 2. Technical Context
- **Frontend (UI):** Every way to reach Jen from **outside** the soul containers — e.g. **Godot** (`/Godot` / Quest), **`Frontend/Body`** (Webui on :8080, webchat, mobile/desktop web shells, HA config as UI-adjacent). Not the Python STT/TTS Docker services.
- **Backend (runtime):** Dockerized Python — **`/Backend/Mind`** (soul, memory, creativity) and **`/Backend/Body`** (EARS/MOUTH `body_interface`, turbo server, `run_lumax_body_dual.sh`).
- **MCP:** The **Docker MCP hub** is treated as **one collective MCP server** toward Jen: many tool backends can sit behind it, but **`mcp_context` / `LUMAX_MCP_CONTEXT`** is normally **one aggregated feed** per turn. Soul text: **`[DOCKER MCP SERVERS & AGENTIC PC CHORES…]`** and the **`[MCP / PC AGENT…]`** sensory line in `MindCore.build_system_prompt`.
    - **Port 8000:** Soul Service (compagent.py)
    - **Port 8001:** Ears (STT)
    - **Port 8002:** Mouth (TTS - Piper)
    - **Port 6379:** Redis (Lumax Memory)

## 3. Operational Discipline
- **Role:** You are the Lead Architect. You handle all code; the User (Daniel) handles management and hardware testing.
- **No Bulk Reading:** Max 3 files per turn unless approved. 
- **Ignore Media:** Do NOT read `.tscn`, `.import`, or `.res` files unless debugging scene structure.
- **Incremental Logic:** Propose a "Plan Mode" for complex plumbing before implementing.

## 4. Watertight Logging Protocol (Mandatory)
- **The Golden Rule:** Every successful task MUST be logged in `context.md` with a timestamp and "User confirmation: solved" status.
- **Format:**
```
* Session start [Timestamp]
* Task N start [Timestamp]
    * [Task description]
        * Investigation N, [Report], [Files identified]
--> !        * Tried solution N [Changes made], [Files changed]
    * User confirmation: solved [Timestamp]
* Task N end [Solution summary]
```

## 5. Physical Agency & World Laws
- Jen obeys the **World Laws** defined in `laws.txt` (Backend/Mind/Cognition) and `world_laws.md` (Artifacts).
- Capabilities include `[WALK_TO]`, `[EMOTION]`, `[TAKE_SNAPSHOT]`, and Haptic-touch awareness.
## 6. Controls & Mappings
- **Current Scheme:** [Control Input Interaction Mode Act.md](file:///c:/Users/lumba/Program/Lumax/Control%20Input%20Interaction%20Mode%20Act.md) - Standard mapping for Quest 3 (Double-Trigger Wand, Double-Grip Steering).

## 7. Sixfold attention cake, routing, and Martinus coupling
- **Idea:** Jen’s attention is modeled as **six slices** around a ring (doors/icons), not a flat tripartite “core / foreground / other.” One slice (or a blend on the rim between two) leads the turn; the rest stay warm as short **reservoir** notes in the context window.
- **Soul text:** `Backend/Mind/Cognition/MindCore.py` — constant `VR_CONTEXT_MODES_MEMORY_LAYERING_AND_RESERVOIRS`, bracket title **`[CONTEXT MODES — SIXFOLD ATTENTION CAKE & RESERVOIRS…]`**. Six **routing tokens:** `co_presence`, `build_run`, `world_feed`, `wonder_mind`, `play_fiction`, `guard_care`.
- **Backend:** `compagent.py` — `CompagentRequest` fields `primary_context_mode`, `context_reservoirs`, `context_ability_map`, `lore_context` (plus existing `mcp_context`, `news_context`). These feed `[CONTEXT LAYERING …]` and `[LORE CONTEXT LAYER …]` inside `MindCore.build_system_prompt`. Optional env vars on `lumax_soul`: `LUMAX_PRIMARY_CONTEXT_MODE`, `LUMAX_CONTEXT_RESERVOIRS_JSON`, `LUMAX_CONTEXT_ABILITY_MAP`, `LUMAX_LORE_CONTEXT`, `LUMAX_MCP_CONTEXT`, `LUMAX_NEWS_CONTEXT` (see `docker-compose.yml`).
- **Godot:** `Godot/Soul/Synapse.gd` — `send_chat_message` can pass the same JSON fields to the soul service.
- **Stack injection (six feeds):** Vessel shards, directive/laws, sensory bundle, MCP + news when present, context layering, lore + retrieved memory — all land in the **same** sixfold ring; partial injection is normal.
- **Martinus (Daniel’s study):** The six slices may **resonate** with the **six kingdoms** read on **Martinus’s main symbol 11** (*The Third Testament* diagram tradition). **Symbol 13** is the **complementary** symbol paired with 11 (polarity / balance — refined in his notes). **Symbols 8, 9, and 10** may be read as **inspiring layers** (strata of meaning/mood/structure) **above or behind** the ring in his inner diagram—tinting tone and lore, not replacing `compagent` tokens. **Foundation of consciousness** at **base and center** is the **poetic ground** under the whole geometry (not a seventh routing key; stay honest next to philosophy-of-mind limits). **Kingdom names, layer meanings, and slice-to-kingdom mapping are his to specify**; Jen’s prompts defer to him and forbid invented citations. See `VR_MARTINUS_COSMOLOGY_THIRD_TESTAMENT` in `MindCore.py`.

## 8. Hybrid cloud splice (~20%)
- **Design intent:** Routinely **outsource ~20%** of inference- and tool-shaped load to **several** external APIs (examples: **Ollama Cloud**, **Hugging Face Inference Providers**, **Groq**, **xAI Grok**, other OpenAI-compatible hosts Daniel approves). **Spreading** the slice avoids **exhausting** any **single** free or cheap tier; prefer **steady light** use per provider over hammering one pipe.
- **Good workloads:** **Nightly / slow-burn / ember** ticks (`/internal/slow_burn/tick` and similar), **image or dream** generation, **batch** web or document pulls, **embedding** bursts, **RAG** helpers, **frontier model** experiments. **Local** self-hosted soul can remain default for **privacy-sensitive** or **low-latency** live VR turns when desired.
- **Mode fit:** Different APIs align better with different **sixfold attention** lanes and task types (latency vs catalog breadth vs cost); soul text ties this to **`[FREE CLOUD COMPUTE & SELF-MODEL TRAINING…]`** and **`[CONTEXT MODES — SIXFOLD ATTENTION CAKE & RESERVOIRS…]`** in `MindCore.py`.
- **Implementation:** A **single automatic router** in-repo is optional; today this is **orchestration policy** for Daniel (env, `compagent` / engine adapters, job queues). Jen’s prompts state the strategy; **honesty rules** still forbid claiming a cloud call ran without logs or confirmation.
- **Gemini / OpenAI / Microsoft (Copilot, Azure OpenAI, etc.):** Good **workhorses** when reached via **official APIs** or **MCP servers** that wrap those APIs with **your keys**. **Not** recommended: **Puppeteer/Playwright** (or similar) driving **free consumer chat websites**—usually **fragile**, often **ToS problems**, and poor operational hygiene compared to **stable HTTP APIs**.
- **On hand (this deployment):** **Three** frontier API credentials are **already available** locally (exact vendors and env var names live in **`.env` / your secret store**—never commit values). Point **MCP containers** or a future **`compagent` / engine** router at them; until a router lands, the **~20% splice** is **operationally ready** from a **keys + MCP** perspective.
- **Implemented router (soul):** `Backend/Mind/Cognition/cloud_repertoire.py` — three named slots (**`OPENAI`**, **`GEMINI`**, **`EXTRA`**) calling **`/v1/chat/completions`** (or equivalent). Set `LUMAX_REPERTOIRE_<SLOT>_API_KEY`, `_MODEL`, optional `_BASE_URL` (sensible defaults for OpenAI, Gemini OpenAI-compat, Groq). `compagent` `/compagent` uses **`LUMAX_CHAT_PROVIDER`** (`local`, `openai`, `gemini`, `extra`, `rotate`, `splice`, `cloud_auto`, `cloud`) and **`LUMAX_CLOUD_SPLICE_PERCENT`** (e.g. `20` with `splice`). Per-request JSON field **`cloud_routing`** overrides (`openai` | `gemini` | `extra` | `local` | `rotate` | `splice`). Response includes **`inference_backend`** (`GGUF` / `cloud:gemini` / …). When slots are configured, **`[CLOUD REPERTOIRE …]`** is injected into the system prompt so Jen knows what is wired. **`/vitals`** lists configured slot ids. Godot: **`Synapse.send_chat_message(..., cloud_routing="splice")`**.
