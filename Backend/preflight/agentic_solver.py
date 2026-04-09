import json
import logging
import os
import subprocess
import time
from typing import Dict, List, Optional

import httpx


logger = logging.getLogger("AgenticSolver")

ALLOWED_ACTIONS = {
    "docker_compose_up",
    "bridge_reverse",
    "recheck_services",
    "sleep_short",
    "refresh_network_config",
    "preflight_standard",
    "preflight_deep",
    "restart_service_soul",
    "restart_service_body",
    "restart_service_turbo",
    "inspect_containers",
    "capture_service_logs",
    "extended_test_probe",
    "request_architecture_plan",
    "none",
}


def _bool_env(name: str, default: bool = False) -> bool:
    v = os.getenv(name, str(default)).strip().lower()
    return v in ("1", "true", "yes", "on")


def _build_prompt(failures: Dict[str, bool]) -> str:
    return (
        "You are a backend sentry healer for Lumax.\n"
        "Given failing services, return strict JSON only with schema:\n"
        '{"actions":[<allowed_action>],"reason":"...","confidence":0.0,"request_approval":false,'
        '"improvement_notes":[],"test_measures":[]}\n'
        "Allowed actions are: "
        + ", ".join(sorted(ALLOWED_ACTIONS))
        + "\n"
        f"Failures: {json.dumps(failures)}\n"
        "Rules: Prefer minimal actions. Never suggest destructive operations.\n"
    )


def _is_temporarily_paused() -> str:
    # Manual pause switch for deploy windows.
    if _bool_env("LUMAX_SENTRY_AGENTIC_PAUSED", False):
        return "agentic-paused-env"
    # Simple file lock, useful from deploy scripts: create lock before rollout, remove after.
    lock_path = os.getenv("LUMAX_SENTRY_DEPLOY_LOCK_PATH", "").strip()
    if lock_path and os.path.exists(lock_path):
        return "agentic-paused-lockfile"
    # Optional time window pause (unix epoch seconds).
    pause_until = os.getenv("LUMAX_SENTRY_PAUSE_UNTIL_EPOCH", "").strip()
    if pause_until:
        try:
            if time.time() < float(pause_until):
                return "agentic-paused-time-window"
        except ValueError:
            pass
    return ""


def _parse_actions(text: str) -> Dict:
    raw = text.strip()
    # Try exact JSON first
    try:
        data = json.loads(raw)
    except Exception:
        # Try extracting first JSON object region
        lb = raw.find("{")
        rb = raw.rfind("}")
        if lb >= 0 and rb > lb:
            try:
                data = json.loads(raw[lb : rb + 1])
            except Exception:
                return {"actions": ["none"], "reason": "unparseable-model-output"}
        else:
            return {"actions": ["none"], "reason": "no-json-found"}

    actions = data.get("actions", [])
    if not isinstance(actions, list):
        actions = ["none"]
    cleaned: List[str] = []
    for a in actions:
        if isinstance(a, str) and a in ALLOWED_ACTIONS:
            cleaned.append(a)
    if not cleaned:
        cleaned = ["none"]
    notes = data.get("improvement_notes", [])
    tests = data.get("test_measures", [])
    if not isinstance(notes, list):
        notes = []
    if not isinstance(tests, list):
        tests = []
    return {
        "actions": cleaned,
        "reason": str(data.get("reason", "")),
        "confidence": float(data.get("confidence", 0.0) or 0.0),
        "request_approval": bool(data.get("request_approval", False)),
        "improvement_notes": [str(x) for x in notes[:12]],
        "test_measures": [str(x) for x in tests[:12]],
    }


def _ollama_solver_base_url(solver_url: str) -> str:
    """Strip /api/generate or /api/chat to get origin for fallbacks."""
    u = (solver_url or "").strip().rstrip("/")
    for suffix in ("/api/generate", "/api/chat"):
        if u.endswith(suffix):
            return u[: -len(suffix)].rstrip("/")
    return u


def _ollama_complete_text(url: str, model: str, prompt: str, timeout: float) -> str:
    """
    Prefer POST /api/generate. Some Ollama builds/proxies return 404 there; retry /api/chat.
    """
    payload_gen = {"model": model, "prompt": prompt, "stream": False}
    base = _ollama_solver_base_url(url)
    gen_url = url if "/api/generate" in url or "/api/chat" in url else f"{base}/api/generate"
    chat_url = f"{base}/api/chat"
    with httpx.Client(timeout=timeout) as client:
        r = client.post(gen_url, json=payload_gen)
        if r.status_code == 404:
            logger.debug("Ollama POST %s -> 404; retrying %s", gen_url, chat_url)
            r2 = client.post(
                chat_url,
                json={
                    "model": model,
                    "messages": [{"role": "user", "content": prompt}],
                    "stream": False,
                },
            )
            r2.raise_for_status()
            body = r2.json()
            msg = body.get("message")
            if isinstance(msg, dict):
                return str(msg.get("content", "")).strip()
            return str(body.get("response", "") or "").strip()
        r.raise_for_status()
        body = r.json()
        return str(body.get("response", "")).strip()


def _solve_with_ollama(prompt: str) -> Dict:
    url = os.getenv("LUMAX_SENTRY_SOLVER_URL", "http://host.docker.internal:11434/api/generate").strip()
    model = os.getenv("LUMAX_SENTRY_SOLVER_MODEL", "qwen2.5-coder:latest").strip()
    timeout = float(os.getenv("LUMAX_SENTRY_SOLVER_TIMEOUT_SEC", "20"))
    text = _ollama_complete_text(url, model, prompt, timeout)
    return _parse_actions(text)


def _solve_text_with_ollama(prompt: str) -> str:
    url = os.getenv("LUMAX_SENTRY_SOLVER_URL", "http://host.docker.internal:11434/api/generate").strip()
    model = os.getenv("LUMAX_SENTRY_SOLVER_MODEL", "qwen2.5-coder:latest").strip()
    timeout = float(os.getenv("LUMAX_SENTRY_SOLVER_TIMEOUT_SEC", "20"))
    return _ollama_complete_text(url, model, prompt, timeout)


def _solve_with_command(prompt: str) -> Dict:
    """
    Command mode for ONNX/TensorRT runner wrappers.
    Env:
      LUMAX_SENTRY_SOLVER_CMD='runner --model qwen2.5-coder-onnx --prompt "{prompt}"'
    """
    cmd_tpl = os.getenv("LUMAX_SENTRY_SOLVER_CMD", "").strip()
    if not cmd_tpl:
        return {"actions": ["none"], "reason": "missing-command-template"}
    cmd = cmd_tpl.replace("{prompt}", prompt.replace('"', '\\"'))
    try:
        proc = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        text = (proc.stdout or proc.stderr or "").strip()
        return _parse_actions(text)
    except Exception as e:
        return {"actions": ["none"], "reason": f"command-error:{e}"}


def _solve_text_with_command(prompt: str) -> str:
    cmd_tpl = os.getenv("LUMAX_SENTRY_SOLVER_CMD", "").strip()
    if not cmd_tpl:
        return "Solver command template is missing."
    cmd = cmd_tpl.replace("{prompt}", prompt.replace('"', '\\"'))
    try:
        proc = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=40)
        return (proc.stdout or proc.stderr or "").strip()
    except Exception as e:
        return f"Solver command failed: {e}"


def _read_unstable_features() -> List[Dict]:
    path = os.getenv("LUMAX_SENTRY_UNSTABLE_FEATURES_PATH", "/app/ops/playbooks/unstable_features.json").strip()
    if not path or not os.path.isfile(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return []
        features = data.get("features", [])
        if not isinstance(features, list):
            return []
        out: List[Dict] = []
        for item in features:
            if isinstance(item, dict) and item.get("name"):
                out.append(item)
        return out
    except Exception as e:
        logger.warning("Could not read unstable feature registry: %s", e)
        return []


def read_unstable_features() -> List[Dict]:
    """Public wrapper for sentry loop usage."""
    return _read_unstable_features()


def _build_architect_prompt(failures: Dict[str, bool], unstable_features: List[Dict], solver_reason: str) -> str:
    return (
        "You are a senior architect for Lumax reliability.\n"
        "Create a concrete implementation proposal for missing/unstable features.\n"
        "Return strict JSON with schema:\n"
        '{"title":"...",'
        '"summary":"...",'
        '"missing_capabilities":["..."],'
        '"proposed_implementation":["..."],'
        '"code_change_candidates":[{"path":"...","change":"..."}],'
        '"extended_tests":["..."],'
        '"safety_guards":["..."],'
        '"requires_user_approval":true}\n'
        f"Current service failures: {json.dumps(failures)}\n"
        f"Unstable feature registry: {json.dumps(unstable_features)}\n"
        f"Current solver reason: {solver_reason}\n"
    )


def propose_architecture_plan(failures: Dict[str, bool], solver_decision: Optional[Dict] = None) -> Dict:
    if not _bool_env("LUMAX_SENTRY_ARCHITECT_ENABLED", False):
        return {
            "title": "architect-disabled",
            "summary": "Architect escalation is disabled.",
            "missing_capabilities": [],
            "proposed_implementation": [],
            "code_change_candidates": [],
            "extended_tests": [],
            "safety_guards": [],
            "requires_user_approval": True,
        }
    cmd_tpl = os.getenv("LUMAX_SENTRY_ARCHITECT_CMD", "").strip()
    if not cmd_tpl:
        return {
            "title": "architect-missing-command",
            "summary": "Architect command template is not configured.",
            "missing_capabilities": [],
            "proposed_implementation": [],
            "code_change_candidates": [],
            "extended_tests": [],
            "safety_guards": [],
            "requires_user_approval": True,
        }

    unstable = _read_unstable_features()
    reason = str((solver_decision or {}).get("reason", ""))
    prompt = _build_architect_prompt(failures, unstable, reason)
    cmd = cmd_tpl.replace("{prompt}", prompt.replace('"', '\\"'))
    try:
        proc = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
        text = (proc.stdout or proc.stderr or "").strip()
        if not text:
            return {
                "title": "architect-empty",
                "summary": "No output from architect model.",
                "missing_capabilities": [],
                "proposed_implementation": [],
                "code_change_candidates": [],
                "extended_tests": [],
                "safety_guards": [],
                "requires_user_approval": True,
            }
        lb = text.find("{")
        rb = text.rfind("}")
        if lb >= 0 and rb > lb:
            text = text[lb : rb + 1]
        data = json.loads(text)
        if not isinstance(data, dict):
            raise ValueError("architect output is not a JSON object")
        data["requires_user_approval"] = True
        return data
    except Exception as e:
        logger.warning("Architect proposal failed: %s", e)
        return {
            "title": "architect-failed",
            "summary": f"Architect proposal failed: {e}",
            "missing_capabilities": [],
            "proposed_implementation": [],
            "code_change_candidates": [],
            "extended_tests": [],
            "safety_guards": [],
            "requires_user_approval": True,
        }


def propose_actions(failures: Dict[str, bool], unstable_features: Optional[List[Dict]] = None) -> Dict:
    """
    Returns:
      {"actions":[...], "reason":"..."}
    """
    if not _bool_env("LUMAX_SENTRY_AGENTIC", False):
        return {"actions": ["none"], "reason": "agentic-disabled"}
    pause_reason = _is_temporarily_paused()
    if pause_reason:
        return {"actions": ["none"], "reason": pause_reason}

    # Default matches docker-compose lumax_ops (command / local runner); set LUMAX_SENTRY_SOLVER_MODE=ollama to use Ollama.
    mode = os.getenv("LUMAX_SENTRY_SOLVER_MODE", "command").strip().lower()
    prompt = _build_prompt(failures)
    if unstable_features:
        prompt += f"Unstable features: {json.dumps(unstable_features)}\n"
    try:
        if mode == "command":
            out = _solve_with_command(prompt)
        else:
            out = _solve_with_ollama(prompt)
        logger.debug("Agentic solver proposed actions=%s reason=%s", out.get("actions"), out.get("reason"))
        return out
    except Exception as e:
        logger.warning("Agentic solver failed: %s", e)
        return {"actions": ["none"], "reason": f"solver-failed:{e}"}


def answer_runtime_question(question: str, context: Dict) -> str:
    """
    Ask solver for an investigation answer using runtime context.
    Returns plain text markdown.
    """
    mode = os.getenv("LUMAX_SENTRY_SOLVER_MODE", "command").strip().lower()
    prompt = (
        "You are Lumax watchdog investigator.\n"
        "Answer with: findings, likely causes, safe checks, and recommended next steps.\n"
        "Do not propose destructive actions.\n"
        f"Question: {question}\n"
        f"Runtime context JSON: {json.dumps(context)[:40000]}\n"
    )
    try:
        if mode == "command":
            text = _solve_text_with_command(prompt)
        else:
            text = _solve_text_with_ollama(prompt)
        txt = (text or "").strip()
        if not txt:
            return _fallback_runtime_answer(question, context, "empty-solver-output")
        # If wrapper returns a degenerate none/reason payload, provide useful local analysis.
        if "runner-error" in txt or "missing-command-template" in txt:
            return _fallback_runtime_answer(question, context, txt[:400])
        return txt
    except Exception as e:
        return _fallback_runtime_answer(question, context, f"solver-exception:{e}")


def _fallback_runtime_answer(question: str, context: Dict, failure_reason: str) -> str:
    failures = context.get("failures", {}) if isinstance(context, dict) else {}
    inspect = context.get("inspect_report", {}) if isinstance(context, dict) else {}
    service_inspect = inspect.get("service_inspect", {}) if isinstance(inspect, dict) else {}
    recent_logs = inspect.get("recent_logs", {}) if isinstance(inspect, dict) else {}

    down = [k for k, v in failures.items() if v]
    likely = []
    if "TURBO" in down:
        likely.append("Turbo service appears unreachable from lumax_ops (DNS/network/container state).")
    if not down:
        likely.append("No service heartbeat failures detected in this cycle.")
    if any("No such file or directory: 'runner'" in str(v) for v in [failure_reason]):
        likely.append("Local ONNX runner command is not available in container PATH.")

    safe_checks = [
        "Verify lumax_turbochat container exists and is on lumax_local network.",
        "Check solver runtime command/env: LUMAX_LOCAL_RUNNER_CMD and LUMAX_SENTRY_SOLVER_CMD.",
        "Keep bridge maintenance active; compare failure signatures across 3 cycles.",
    ]
    if "animation" in question.lower():
        safe_checks.extend(
            [
                "Capture latest Godot animation diagnostics and compare player path/root_node consistency.",
                "Temporarily keep startup auto greeting disabled while validating idle path only.",
            ]
        )

    return (
        "## Watchdog fallback investigation\n"
        f"- Solver reason: {failure_reason}\n"
        f"- Failing services: {down if down else ['none']}\n"
        f"- Likely causes: {likely}\n"
        f"- Safe next checks: {safe_checks}\n"
        f"- Evidence keys: service_inspect={list(service_inspect.keys())[:8]}, recent_logs={list(recent_logs.keys())[:8]}\n"
    )

