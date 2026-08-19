#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/clipfactory-site"
RUNTIME="$HOME/.clipfactory"
mkdir -p "$RUNTIME"

echo "================================"
echo "       CLIPFACTORY START"
echo "================================"

# 1. Bridge TikTok
if curl -s --max-time 2 http://127.0.0.1:8787/health \
   | grep -q '"ok": true'; then
    echo "✅ Bridge TikTok déjà actif"
else
    echo "🚀 Démarrage bridge TikTok..."

    cd "$ROOT"

    nohup python local-api/server.py \
      > "$RUNTIME/bridge.log" 2>&1 &

    echo $! > "$RUNTIME/bridge.pid"

    sleep 2

    if curl -s --max-time 3 http://127.0.0.1:8787/health \
       | grep -q '"ok": true'; then
        echo "✅ Bridge TikTok actif"
    else
        echo "❌ Bridge TikTok non démarré"
        cat "$RUNTIME/bridge.log"
        exit 1
    fi
fi

# 2. Interface web
if curl -s --max-time 2 http://127.0.0.1:8080/ \
   >/dev/null 2>&1; then

    echo "✅ Interface déjà active"

else

    echo "🌐 Démarrage interface..."

    cd "$ROOT"

    nohup python -m http.server 8080 \
      --bind 127.0.0.1 \
      > "$RUNTIME/web.log" 2>&1 &

    echo $! > "$RUNTIME/web.pid"

    sleep 2

fi

echo
echo "🤖 Démarrage Autopilot Worker..."

"$ROOT/scripts/start-autopilot-worker.sh" || true

echo
echo "🛡️ Démarrage watchdog..."

"$ROOT/scripts/start-watchdog.sh" || true

echo
echo "================================"
echo "✅ CLIPFACTORY PRÊT"
echo "================================"
echo
echo "Interface :"
echo "http://127.0.0.1:8080/"
echo
echo "Bridge TikTok :"
echo "http://127.0.0.1:8787/health"
echo

# Android : ouvre automatiquement ClipFactory
termux-open-url "http://127.0.0.1:8080/" 2>/dev/null || true
