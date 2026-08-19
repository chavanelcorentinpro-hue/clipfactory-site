#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

MODE="${1:-prepare}"

ROOT="$HOME/tiktok_factory"
RUNTIME="$HOME/.clipfactory"
META="$RUNTIME/last_post.json"
LOG="$RUNTIME/oneclick.log"

mkdir -p "$RUNTIME"

echo "================================"
echo "       CLIPFACTORY ONE CLICK"
echo "================================"
echo "Mode : $MODE"

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

if [ -z "${FILE:-}" ] || [ ! -f "$FILE" ]; then
  echo "❌ Aucune vidéo finale trouvée"
  exit 1
fi

PROJECT=$(basename "$(dirname "$(dirname "$FILE")")")

if [ -z "$PROJECT" ] || [ "$PROJECT" = "tmp" ]; then
  PROJECT="ClipFactory"
fi

TITLE=$(echo "$PROJECT" | tr '_-' '  ' | sed 's/  */ /g')

case "$PROJECT" in
  *travel*)
    HASHTAGS="#travel #voyage #tiktok #clipfactory"
    ;;
  *cinema*|*emotion*)
    HASHTAGS="#cinema #emotion #story #clipfactory"
    ;;
  *karaoke*|*music*)
    HASHTAGS="#music #karaoke #tiktok #clipfactory"
    ;;
  *)
    HASHTAGS="#tiktok #viral #video #clipfactory"
    ;;
esac

INFO=$(ffprobe -v error \
  -select_streams v:0 \
  -show_entries stream=codec_name,width,height \
  -show_entries format=duration,size \
  -of default=noprint_wrappers=1 "$FILE")

CODEC=$(printf '%s\n' "$INFO" | awk -F= '/codec_name/{print $2;exit}')
WIDTH=$(printf '%s\n' "$INFO" | awk -F= '/width/{print $2;exit}')
HEIGHT=$(printf '%s\n' "$INFO" | awk -F= '/height/{print $2;exit}')
DURATION=$(printf '%s\n' "$INFO" | awk -F= '/duration/{print $2;exit}')
SIZE=$(printf '%s\n' "$INFO" | awk -F= '/size/{print $2;exit}')

python - "$META" "$FILE" "$TITLE" "$HASHTAGS" "$PROJECT" "$CODEC" "$WIDTH" "$HEIGHT" "$DURATION" "$SIZE" <<'PY'
import json,sys,datetime

(
    out,
    video,
    title,
    hashtags,
    project,
    codec,
    width,
    height,
    duration,
    size
) = sys.argv[1:]

data = {
    "video": video,
    "title": title,
    "hashtags": hashtags,
    "project": project,
    "codec": codec,
    "width": int(width or 0),
    "height": int(height or 0),
    "duration": float(duration or 0),
    "size": int(size or 0),
    "result": "prepared",
    "created_at": datetime.datetime.now().isoformat()
}

with open(out, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY

echo
echo "🎬 Vidéo : $FILE"
echo "📝 Titre : $TITLE"
echo "🏷️  Hashtags : $HASHTAGS"
echo "📐 ${WIDTH}x${HEIGHT}"
echo "⏱️  ${DURATION}s"
echo

if [ "$MODE" = "prepare" ]; then
  echo "✅ PRÉPARATION TERMINÉE"
  echo "Aucun envoi TikTok effectué."
  exit 0
fi

if [ "$MODE" != "publish" ]; then
  echo "❌ Mode inconnu : $MODE"
  echo "Utilise : prepare ou publish"
  exit 1
fi

echo "🚀 Envoi TikTok..."

RESULT="error"

if "$HOME/clipfactory-site/scripts/tiktok-upload.sh" "$FILE"; then
    RESULT="success"
fi

python - "$META" "$RESULT" <<'PY'
import json,sys,datetime

p,result=sys.argv[1:]
d=json.load(open(p, encoding="utf-8"))
d["result"]=result
d["finished_at"]=datetime.datetime.now().isoformat()

with open(p,"w",encoding="utf-8") as f:
    json.dump(d,f,indent=2,ensure_ascii=False)
PY

{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')]"
  echo "FILE=$FILE"
  echo "TITLE=$TITLE"
  echo "HASHTAGS=$HASHTAGS"
  echo "RESULT=$RESULT"
  echo
} >> "$LOG"

if [ "$RESULT" = "success" ]; then
  echo "✅ CLIPFACTORY TERMINÉ"
  exit 0
fi

echo "❌ ÉCHEC CLIPFACTORY"
exit 1
