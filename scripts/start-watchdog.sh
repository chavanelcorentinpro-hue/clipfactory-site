#!/data/data/com.termux/files/usr/bin/bash

ROOT="$HOME/clipfactory-site"
RUNTIME="$HOME/.clipfactory"

mkdir -p "$RUNTIME"

PIDFILE="$RUNTIME/watchdog.pid"

if [ -f "$PIDFILE" ]; then

  PID="$(cat "$PIDFILE")"

  if kill -0 "$PID" 2>/dev/null; then
    echo "✅ Watchdog already running"
    echo "PID: $PID"
    exit 0
  fi

fi

nohup sh -c "
while true
do
  '$ROOT/scripts/clipfactory-watchdog.sh'
  sleep 60
done
" > "$RUNTIME/watchdog.out" 2>&1 &

PID=$!

echo "$PID" > "$PIDFILE"

echo "✅ WATCHDOG STARTED"
echo "PID: $PID"
