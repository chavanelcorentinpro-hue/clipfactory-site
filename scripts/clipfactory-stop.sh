#!/data/data/com.termux/files/usr/bin/bash

RUNTIME="$HOME/.clipfactory"

"$HOME/clipfactory-site/scripts/stop-watchdog.sh" \
    2>/dev/null || true

"$HOME/clipfactory-site/scripts/stop-autopilot-worker.sh" \
    2>/dev/null || true

for PIDFILE in \
    "$RUNTIME/bridge.pid" \
    "$RUNTIME/web.pid"
do

    if [ -f "$PIDFILE" ]; then

        PID=$(cat "$PIDFILE" 2>/dev/null || true)

        if [ -n "$PID" ]; then
            kill "$PID" 2>/dev/null || true
        fi

        rm -f "$PIDFILE"
    fi
done

pkill -f "local-api/server.py" \
    2>/dev/null || true

pkill -f "http.server 8080" \
    2>/dev/null || true

termux-wake-unlock \
    2>/dev/null || true

echo "✅ CLIPFACTORY STOPPED"
