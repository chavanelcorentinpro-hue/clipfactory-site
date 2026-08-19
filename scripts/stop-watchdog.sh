#!/data/data/com.termux/files/usr/bin/bash

PIDFILE="$HOME/.clipfactory/watchdog.pid"

if [ ! -f "$PIDFILE" ]; then
  echo "Watchdog not running"
  exit 0
fi

PID="$(cat "$PIDFILE")"

kill "$PID" 2>/dev/null || true

rm -f "$PIDFILE"

echo "✅ WATCHDOG STOPPED"
