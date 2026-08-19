#!/data/data/com.termux/files/usr/bin/bash

echo "================================"
echo "      CLIPFACTORY HEALTH"
echo "================================"
echo

check_http() {

    NAME="$1"
    URL="$2"

    if curl -s --max-time 3 "$URL" >/dev/null 2>&1; then
        echo "✅ $NAME"
    else
        echo "❌ $NAME"
    fi
}

check_pid() {

    NAME="$1"
    FILE="$2"

    if [ -f "$FILE" ]; then

        PID=$(cat "$FILE" 2>/dev/null || true)

        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo "✅ $NAME (PID $PID)"
            return
        fi
    fi

    echo "❌ $NAME"
}

check_http \
    "Web interface" \
    "http://127.0.0.1:8080/"

check_http \
    "Local bridge" \
    "http://127.0.0.1:8787/health"

check_pid \
    "Autopilot worker" \
    "$HOME/.clipfactory/autopilot-worker.pid"

check_pid \
    "Watchdog" \
    "$HOME/.clipfactory/watchdog.pid"

echo
echo "=== AUTOPILOT ==="

python \
"$HOME/clipfactory-site/scripts/clipfactory-autopilot.py" \
2>/dev/null || true

echo
echo "=== QUEUE ==="

python \
"$HOME/clipfactory-site/scripts/clipfactory-queue.py" \
2>/dev/null \
| head -40

echo
echo "=== SCHEDULE ==="

python \
"$HOME/clipfactory-site/scripts/clipfactory-scheduler.py" \
2>/dev/null \
| head -40

echo
echo "=== TIKTOK TOKEN ==="

python - <<'PY'
import json
from pathlib import Path

p = Path.home() / "tiktok_token.json"

try:
    d = json.loads(p.read_text())
    print("✅ Token present")
    print("Scopes:", d.get("scope"))
    print("Access expires:", d.get("expires_in"))
    print("Refresh expires:", d.get("refresh_expires_in"))
except Exception:
    print("❌ TikTok token unavailable")
PY

echo
echo "================================"
echo "      HEALTH CHECK DONE"
echo "================================"
