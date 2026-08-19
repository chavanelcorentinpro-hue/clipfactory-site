#!/data/data/com.termux/files/usr/bin/bash
set -e

FILE="${1:-}"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    echo "Usage: ./scripts/tiktok-upload.sh /chemin/video.mp4"
    exit 1
fi

echo "🔐 Vérification accès TikTok..."

"$HOME/clipfactory-site/scripts/tiktok-refresh.sh" || {
    echo "❌ Impossible de renouveler l'accès TikTok"
    exit 1
}

TOKEN=$(python -c 'import json,os; print(json.load(open(os.path.expanduser("~/tiktok_token.json")))["access_token"])')

if [ -z "$TOKEN" ]; then
    echo "❌ Access token TikTok absent"
    exit 1
fi

echo "✅ Accès TikTok prêt"

SIZE=$(stat -c%s "$FILE")
LAST=$((SIZE-1))

QUOTA_LOCK="$HOME/.clipfactory/tiktok_quota.lock"

if [ -f "$QUOTA_LOCK" ]; then

    NOW=$(date +%s)

    LOCK_TIME=$(stat -c %Y "$QUOTA_LOCK" 2>/dev/null || echo 0)

    AGE=$((NOW - LOCK_TIME))

    # 24-hour defensive cooldown
    if [ "$AGE" -lt 86400 ]; then

        REMAIN=$((86400 - AGE))

        echo "⚠️ TikTok quota cooldown active"
        echo "Retry in approximately $((REMAIN / 3600)) hour(s)."

        exit 2

    else

        rm -f "$QUOTA_LOCK"

    fi

fi


echo "🎬 ClipFactory → TikTok"
echo "Fichier : $FILE"
echo "Taille : $SIZE octets"

INIT=$(curl -sS -X POST \
"https://open.tiktokapis.com/v2/post/publish/inbox/video/init/" \
-H "Authorization: Bearer $TOKEN" \
-H "Content-Type: application/json; charset=UTF-8" \
-d "{\"source_info\":{\"source\":\"FILE_UPLOAD\",\"video_size\":$SIZE,\"chunk_size\":$SIZE,\"total_chunk_count\":1}}")

PUBLISH_ID=$(printf '%s' "$INIT" | python -c \
'import sys,json; print(json.load(sys.stdin).get("data",{}).get("publish_id",""))')

UPLOAD_URL=$(printf '%s' "$INIT" | python -c \
'import sys,json; print(json.load(sys.stdin).get("data",{}).get("upload_url",""))')

if [ -z "$UPLOAD_URL" ]; then

    echo "❌ Initialisation TikTok impossible"

    echo "$INIT" | python -m json.tool

    if echo "$INIT"        | grep -q "spam_risk_too_many_pending_share"; then

        touch "$QUOTA_LOCK"

        echo
        echo "⚠️ TikTok quota circuit breaker activated."
        echo "ClipFactory will avoid repeated retries."

    fi

    unset TOKEN
    exit 1
fi

echo "📤 Upload..."

HTTP=$(curl -sS \
-o $HOME/.clipfactory/tiktok_put_response \
-w "%{http_code}" \
-X PUT "$UPLOAD_URL" \
-H "Content-Type: video/mp4" \
-H "Content-Length: $SIZE" \
-H "Content-Range: bytes 0-$LAST/$SIZE" \
--data-binary "@$FILE")

if [ "$HTTP" != "201" ]; then
    echo "❌ Upload TikTok HTTP $HTTP"
    cat $HOME/.clipfactory/tiktok_put_response
    unset TOKEN
    exit 1
fi

echo "✅ Upload terminé"
echo "TikTok ID : $PUBLISH_ID"
echo "⏳ Traitement..."

for i in $(seq 1 30); do

    RESPONSE=$(curl -sS -X POST \
    "https://open.tiktokapis.com/v2/post/publish/status/fetch/" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json; charset=UTF-8" \
    -d "{\"publish_id\":\"$PUBLISH_ID\"}")

    STATUS=$(printf '%s' "$RESPONSE" | python -c \
    'import sys,json; print(json.load(sys.stdin).get("data",{}).get("status","UNKNOWN"))')

    echo "[$i] $STATUS"

    case "$STATUS" in

        SEND_TO_USER_INBOX)
            echo
            echo "✅ VIDÉO ENVOYÉE À TIKTOK"
            echo "📱 Ouvre TikTok pour terminer la publication."
            unset TOKEN
            exit 0
            ;;

        PUBLISH_COMPLETE)
            echo
            echo "✅ VIDÉO PUBLIÉE"
            unset TOKEN
            exit 0
            ;;

        FAILED)
            echo
            echo "❌ TikTok a refusé la vidéo"
            echo "$RESPONSE" | python -m json.tool
            unset TOKEN
            exit 1
            ;;
    esac

    sleep 10
done

echo "⚠️ Traitement toujours en cours."
echo "Publish ID : $PUBLISH_ID"

unset TOKEN
