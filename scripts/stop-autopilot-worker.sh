#!/data/data/com.termux/files/usr/bin/bash

PIDFILE="$HOME/.clipfactory/autopilot-worker.pid"

if [ ! -f "$PIDFILE" ]; then
    echo "Autopilot worker not running"
    exit 0
fi

PID=$(cat "$PIDFILE")

kill "$PID" 2>/dev/null || true

rm -f "$PIDFILE"

echo "✅ AUTOPILOT WORKER STOPPED"
