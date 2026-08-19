#!/data/data/com.termux/files/usr/bin/bash
set -e

FILE="${1:-}"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    echo "Usage: ./scripts/tiktok-upload.sh /chemin/video.mp4"
    exit 1
fi

TOKEN=$(python -c 'import json,os; print(json.load(open(os.path.expanduser("~/tiktok_token.json")))["access_token"])')

SIZE=$(stat -c%s "$FILE")
LAST=$((SIZE-1))

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
    unset TOKEN
    exit 1
fi

echo "📤 Upload..."

HTTP=$(curl -sS \
-o /tmp/clipfactory_tiktok_response \
-w "%{http_code}" \
-X PUT "$UPLOAD_URL" \
-H "Content-Type: video/mp4" \
-H "Content-Length: $SIZE" \
-H "Content-Range: bytes 0-$LAST/$SIZE" \
--data-binary "@$FILE")

if [ "$HTTP" != "201" ]; then
    echo "❌ Upload TikTok HTTP $HTTP"
    cat /tmp/clipfactory_tiktok_response
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
