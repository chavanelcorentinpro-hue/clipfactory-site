#!/data/data/com.termux/files/usr/bin/bash
set -u

ROOT="$HOME/clipfactory-site"
RUNTIME="$HOME/.clipfactory"

mkdir -p "$RUNTIME"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" \
    >> "$RUNTIME/watchdog.log"
}

is_alive() {
  local pidfile="$1"

  [ -f "$pidfile" ] || return 1

  local pid
  pid="$(cat "$pidfile" 2>/dev/null)"

  [ -n "$pid" ] || return 1

  kill -0 "$pid" 2>/dev/null
}

start_bridge() {

  if curl -s --max-time 2 \
    http://127.0.0.1:8787/health \
    | grep -q '"ok": true'
  then
    return 0
  fi

  log "Restart bridge"

  nohup python \
    "$ROOT/local-api/server.py" \
    > "$RUNTIME/bridge.log" 2>&1 &

  echo $! > "$RUNTIME/bridge.pid"
}

start_web() {

  if curl -s --max-time 2 \
    http://127.0.0.1:8080/ \
    >/dev/null 2>&1
  then
    return 0
  fi

  log "Restart web server"

  cd "$ROOT" || return 1

  nohup python -m http.server 8080 \
    --bind 127.0.0.1 \
    > "$RUNTIME/web.log" 2>&1 &

  echo $! > "$RUNTIME/web.pid"
}

start_worker() {

  local pidfile="$RUNTIME/autopilot-worker.pid"

  if is_alive "$pidfile"; then
    return 0
  fi

  rm -f "$pidfile"

  log "Restart autopilot worker"

  "$ROOT/scripts/start-autopilot-worker.sh" \
    >> "$RUNTIME/watchdog.log" 2>&1
}

repair_stuck_queue() {

python - <<'PY'
import json
from pathlib import Path
from datetime import datetime, timedelta

runtime = Path.home() / ".clipfactory"
queue_file = runtime / "queue.json"
schedule_file = runtime / "schedule.json"

limit = datetime.now() - timedelta(minutes=20)

def load(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"items":[]}

def save(path, data):
    path.write_text(
        json.dumps(
            data,
            indent=2,
            ensure_ascii=False
        ),
        encoding="utf-8"
    )

q = load(queue_file)
changed = False

for item in q.get("items", []):
    if item.get("state") != "SENDING":
        continue

    try:
        updated = datetime.fromisoformat(
            item.get("updated_at", "")
        )
    except Exception:
        continue

    if updated < limit:
        item["state"] = "RETRY"
        item["last_error"] = \
            "Recovered after interrupted worker"
        item["updated_at"] = \
            datetime.now().isoformat(timespec="seconds")
        changed = True

if changed:
    save(queue_file, q)

s = load(schedule_file)
changed = False

for item in s.get("items", []):
    if item.get("state") != "SENDING":
        continue

    try:
        updated = datetime.fromisoformat(
            item.get("updated_at", "")
        )
    except Exception:
        continue

    if updated < limit:
        item["state"] = "DUE"
        item["updated_at"] = \
            datetime.now().isoformat(timespec="seconds")
        changed = True

if changed:
    save(schedule_file, s)
PY

}

start_bridge
start_web
start_worker
repair_stuck_queue

log "Watchdog cycle OK"
