#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

SCHED="$HOME/clipfactory-site/scripts/clipfactory-scheduler.py"
QUEUE="$HOME/clipfactory-site/scripts/clipfactory-queue.py"
UPLOAD="$HOME/clipfactory-site/scripts/tiktok-upload.sh"

ITEM=$(
python - <<'PY'
import json
import subprocess

raw=subprocess.check_output(
    [
        "python",
        "/data/data/com.termux/files/home/clipfactory-site/scripts/clipfactory-scheduler.py"
    ],
    text=True
)

d=json.loads(raw)

item=d.get("due")

if item:
    print(
        json.dumps(
            item,
            ensure_ascii=False
        )
    )
PY
)

if [ -z "$ITEM" ]; then

    echo "✅ Aucune vidéo DUE"
    exit 0

fi


ID=$(printf '%s' "$ITEM" | python -c \
'import sys,json; print(json.load(sys.stdin)["queue_id"])')

FILE=$(printf '%s' "$ITEM" | python -c \
'import sys,json; print(json.load(sys.stdin)["file"])')


echo "================================"
echo " CLIPFACTORY SCHEDULED WORKER"
echo "================================"
echo
echo "QUEUE ID : $ID"
echo "FILE     : $FILE"
echo


python - "$ID" <<'PY'
import sys
import importlib.util

spec=importlib.util.spec_from_file_location(
    "queue",
    "/data/data/com.termux/files/home/clipfactory-site/scripts/clipfactory-queue.py"
)

q=importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)

q.mark(
    sys.argv[1],
    "SENDING"
)
PY


python - "$ID" <<'PY'
import sys
import importlib.util

spec=importlib.util.spec_from_file_location(
    "scheduler",
    "/data/data/com.termux/files/home/clipfactory-site/scripts/clipfactory-scheduler.py"
)

m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

m.mark(
    sys.argv[1],
    "SENDING"
)
PY


if "$UPLOAD" "$FILE"; then

python - "$ID" <<'PY'
import sys
import importlib.util

def load(path, name):

    spec=importlib.util.spec_from_file_location(
        name,
        path
    )

    m=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)

    return m


q=load(
    "/data/data/com.termux/files/home/clipfactory-site/scripts/clipfactory-queue.py",
    "queue"
)

s=load(
    "/data/data/com.termux/files/home/clipfactory-site/scripts/clipfactory-scheduler.py",
    "scheduler"
)

qid=sys.argv[1]

q.mark(
    qid,
    "SENT"
)

s.mark(
    qid,
    "SENT"
)
PY

    echo
    echo "✅ SCHEDULED VIDEO SENT"

else

python - "$ID" <<'PY'
import sys
import importlib.util

def load(path, name):

    spec=importlib.util.spec_from_file_location(
        name,
        path
    )

    m=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)

    return m


q=load(
    "/data/data/com.termux/files/home/clipfactory-site/scripts/clipfactory-queue.py",
    "queue"
)

s=load(
    "/data/data/com.termux/files/home/clipfactory-site/scripts/clipfactory-scheduler.py",
    "scheduler"
)

qid=sys.argv[1]

q.mark(
    qid,
    "FAILED",
    "Scheduled TikTok upload failed"
)

s.mark(
    qid,
    "FAILED"
)
PY

    echo
    echo "❌ SCHEDULED VIDEO FAILED"
    exit 1

fi
