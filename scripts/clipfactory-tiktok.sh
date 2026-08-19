#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$HOME/tiktok_factory"
LOGDIR="$HOME/.clipfactory/logs"

mkdir -p "$LOGDIR"

echo "================================="
echo "   CLIPFACTORY → TIKTOK"
echo "================================="

echo
echo "🔎 Recherche de la vidéo finale..."

# Priorité aux fichiers typiquement finaux
FILE=$(
  find "$ROOT" -type f \
    \( -iname "joined.mp4" \
       -o -iname "final.mp4" \
       -o -iname "output.mp4" \
       -o -iname "result.mp4" \) \
    -printf '%T@ %p\n' 2>/dev/null \
  | sort -nr \
  | head -1 \
  | cut -d' ' -f2-
)

# Repli : MP4 récent suffisamment gros
if [ -z "${FILE:-}" ]; then
  FILE=$(
    find "$ROOT" -type f -iname "*.mp4" -size +500k \
      -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -1 \
    | cut -d' ' -f2-
  )
fi

if [ -z "${FILE:-}" ] || [ ! -f "$FILE" ]; then
  echo "❌ Aucune vidéo trouvée"
  exit 1
fi

echo "✅ Vidéo sélectionnée :"
echo "$FILE"

echo
echo "🎞 Vérification..."

INFO=$(ffprobe -v error \
  -select_streams v:0 \
  -show_entries stream=codec_name,width,height \
  -show_entries format=duration,size \
  -of default=noprint_wrappers=1 "$FILE")

echo "$INFO"

CODEC=$(printf '%s\n' "$INFO" | awk -F= '/codec_name/{print $2;exit}')
WIDTH=$(printf '%s\n' "$INFO" | awk -F= '/width/{print $2;exit}')
HEIGHT=$(printf '%s\n' "$INFO" | awk -F= '/height/{print $2;exit}')

if [ "$CODEC" != "h264" ]; then
  echo "⚠️ Codec actuel : $CODEC"
fi

if [ "${HEIGHT:-0}" -le "${WIDTH:-0}" ]; then
  echo "⚠️ La vidéo n'est pas verticale."
fi

echo
echo "🚀 Envoi vers TikTok..."

START=$(date '+%Y-%m-%d %H:%M:%S')

OUTPUT=$(
  "$HOME/clipfactory-site/scripts/tiktok-upload.sh" "$FILE" 2>&1
) || {
  echo "$OUTPUT"
  echo
  echo "❌ Échec TikTok"

  {
    echo "[$START]"
    echo "FILE=$FILE"
    echo "RESULT=FAILED"
    echo "$OUTPUT"
    echo
  } >> "$LOGDIR/tiktok.log"

  exit 1
}

echo "$OUTPUT"

RESULT="UNKNOWN"

if echo "$OUTPUT" | grep -q "SEND_TO_USER_INBOX\|VIDÉO ENVOYÉE À TIKTOK"; then
  RESULT="SEND_TO_USER_INBOX"
fi

if echo "$OUTPUT" | grep -q "VIDÉO PUBLIÉE\|PUBLISH_COMPLETE"; then
  RESULT="PUBLISH_COMPLETE"
fi

{
  echo "[$START]"
  echo "FILE=$FILE"
  echo "RESULT=$RESULT"
  echo "$OUTPUT" | grep -E 'TikTok ID|Publish ID|SEND_TO_USER_INBOX|PUBLISH_COMPLETE|VIDÉO'
  echo
} >> "$LOGDIR/tiktok.log"

echo
echo "================================="
echo "✅ CLIPFACTORY TERMINÉ"
echo "Résultat : $RESULT"
echo "================================="
