#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

QUEUE="$HOME/clipfactory-site/scripts/clipfactory-queue.py"

python "$QUEUE" discover >/dev/null

ITEM=$(python - <<'PY'
import json
import subprocess

raw=subprocess.check_output(
    [
        "python",
        "/data/data/com.termux/files/home/clipfactory-site/scripts/clipfactory-queue.py"
    ],
    text=True
)

d=json.loads(raw)

item=d.get("next")

if not item:
    print("")
else:
    print(
        json.dumps(
            item,
            ensure_ascii=False
        )
    )
PY
)

if [ -z "$ITEM" ]; then
    echo "✅ Queue vide"
    exit 0
fi

ID=$(printf '%s' "$ITEM" | python -c \
'import sys,json; print(json.load(sys.stdin)["id"])')

FILE=$(printf '%s' "$ITEM" | python -c \
'import sys,json; print(json.load(sys.stdin)["file"])')

echo "================================"
echo " CLIPFACTORY QUEUE WORKER"
echo "================================"
echo
echo "ID   : $ID"
echo "FILE : $FILE"
echo

python - "$ID" <<'PY'
import sys
sys.path.insert(
    0,
    "/data/data/com.termux/files/home/clipfactory-site/scripts"
)
import importlib.util

spec=importlib.util.spec_from_file_location(
    "queue",
    "/data/data/com.termux/files/home/clipfactory-site/scripts/clipfactory-queue.py"
)

m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

m.mark(
    sys.argv[1],
    "SENDING"
)
PY

if "$HOME/clipfactory-site/scripts/tiktok-upload.sh" "$FILE"; then

    python - "$ID" <<'PY'
import sys,importlib.util

spec=importlib.util.spec_from_file_location(
    "queue",
    "/data/data/com.termux/files/home/clipfactory-site/scripts/clipfactory-queue.py"
)

m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

m.mark(
    sys.argv[1],
    "SENT"
)
PY

    echo
    echo "✅ SENT"

else

    python - "$ID" <<'PY'
import sys,importlib.util

spec=importlib.util.spec_from_file_location(
    "queue",
    "/data/data/com.termux/files/home/clipfactory-site/scripts/clipfactory-queue.py"
)

m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

m.mark(
    sys.argv[1],
    "FAILED",
    "TikTok upload failed"
)
PY

    echo
    echo "❌ FAILED"

    exit 1
fi
