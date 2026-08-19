#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/clipfactory-site" || exit 1

echo "🚀 Démarrage ClipFactory Bridge..."

exec python local-api/server.py
