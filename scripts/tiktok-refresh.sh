#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ENV="$HOME/.clipfactory/tiktok.env"
TOKEN_FILE="$HOME/tiktok_token.json"
TMP="$HOME/.clipfactory/tiktok_token.tmp"

if [ ! -f "$ENV" ]; then
    echo "❌ Identifiants TikTok introuvables"
    exit 1
fi

if [ ! -f "$TOKEN_FILE" ]; then
    echo "❌ $TOKEN_FILE introuvable"
    exit 1
fi

source "$ENV"

REFRESH_TOKEN=$(python - <<'PY'
import json, os
p=os.path.expanduser("~/tiktok_token.json")
print(json.load(open(p))["refresh_token"])
PY
)

echo "🔄 Renouvellement du token TikTok..."

HTTP=$(curl -sS \
-o "$TMP" \
-w "%{http_code}" \
-X POST "https://open.tiktokapis.com/v2/oauth/token/" \
-H "Content-Type: application/x-www-form-urlencoded" \
--data-urlencode "client_key=$TIKTOK_CLIENT_KEY" \
--data-urlencode "client_secret=$TIKTOK_CLIENT_SECRET" \
--data-urlencode "grant_type=refresh_token" \
--data-urlencode "refresh_token=$REFRESH_TOKEN")

if [ "$HTTP" != "200" ]; then
    echo "❌ TikTok HTTP $HTTP"
    python -m json.tool "$TMP" 2>/dev/null || cat "$TMP"
    rm -f "$TMP"
    unset REFRESH_TOKEN TIKTOK_CLIENT_KEY TIKTOK_CLIENT_SECRET
    exit 1
fi

# Vérifie que TikTok a réellement renvoyé un access_token
python - "$TMP" <<'PY'
import json,sys

p=sys.argv[1]
d=json.load(open(p))

if not d.get("access_token"):
    print("❌ Aucun access_token reçu")
    print(json.dumps(d,indent=2))
    raise SystemExit(1)

print("✅ Nouveau token reçu")
print("expires_in :", d.get("expires_in"))
print("refresh_expires_in :", d.get("refresh_expires_in"))
print("scope :", d.get("scope"))
PY

chmod 600 "$TMP"
mv "$TMP" "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

unset REFRESH_TOKEN TIKTOK_CLIENT_KEY TIKTOK_CLIENT_SECRET

echo
echo "✅ TOKEN TIKTOK RENOUVELÉ"
echo "🔒 Token sauvegardé localement"
