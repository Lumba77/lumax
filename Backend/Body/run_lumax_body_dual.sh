#!/bin/sh
# lumax_body: EARS (STT, :8001) + MOUTH (TTS, :8002) in one container. MODE is read at import in body_interface.py.
cd /app/Backend/Body || exit 1

echo "LUMAX_BODY: Starting EARS (STT) on :8001 ..."
MODE=EARS python -m uvicorn body_interface:app --host 0.0.0.0 --port 8001 &
EARS_PID=$!

# Give Whisper/torch a moment to import; fail fast if EARS never bound (no curl required)
_ears_health() {
  python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/health', timeout=2).read()" 2>/dev/null
}
i=0
while [ "$i" -lt 45 ]; do
  if _ears_health; then
    echo "LUMAX_BODY: EARS healthy on :8001 (pid $EARS_PID)"
    break
  fi
  if ! kill -0 "$EARS_PID" 2>/dev/null; then
    echo "LUMAX_BODY: ERROR — EARS process exited before /health OK. Check logs for STT/Whisper/torch import errors."
    exit 1
  fi
  i=$((i + 1))
  sleep 1
done
if ! _ears_health; then
  echo "LUMAX_BODY: ERROR — EARS /health not ready after 45s (Whisper model download or GPU init?)"
  exit 1
fi

echo "LUMAX_BODY: Starting MOUTH (TTS) on :8002 (foreground) ..."
export MODE=MOUTH
exec python -m uvicorn body_interface:app --host 0.0.0.0 --port 8002
