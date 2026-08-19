#!/data/data/com.termux/files/usr/bin/bash

ROOT="$HOME/clipfactory-site"
RUNTIME="$HOME/.clipfactory"

mkdir -p "$RUNTIME"

if [ -f "$RUNTIME/autopilot-worker.pid" ]; then

    PID=$(cat "$RUNTIME/autopilot-worker.pid")

    if kill -0 "$PID" 2>/dev/null; then

        echo "✅ Autopilot worker already running"
        echo "PID: $PID"
        exit 0

    fi

fi

nohup python \
"$ROOT/scripts/clipfactory-autopilot-worker.py" \
> "$RUNTIME/autopilot-worker.out" 2>&1 &

PID=$!

echo "$PID" \
> "$RUNTIME/autopilot-worker.pid"

sleep 1

if kill -0 "$PID" 2>/dev/null; then

    echo "✅ AUTOPILOT WORKER STARTED"
    echo "PID: $PID"

else

    echo "❌ Worker failed to start"
    cat "$RUNTIME/autopilot-worker.out"
    exit 1

fi
