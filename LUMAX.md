## 1. Project Overview & Jen’s Role
- **Lumax (Standalone):** The sovereign successor to VR-Compagent. An immersive AI companion ecosystem for Meta Quest. Jen (Jenny Forbee) is the soul of this machine — a vision-capable, multimodal AI living in a 2.5D vessel within an XR space.
- **Solaris Phase:** We have decoupled from the legacy junk. This is a clean, functional frontier focused on deep vision integration, haptic-aware intimacy, and autonomous physical will.

## 2. Technical Context
- **Frontend:** Godot 4.4+ (Standalone at /Godot). Targeting Meta Quest 2/3 with OpenXR.
- **Backend:** Dockerized services (Standalone at /Backend/Mind and /Backend/Body).
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
