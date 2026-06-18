#!/usr/bin/env bash
# Per-profile FFmpeg bitrate ladder. H.264 for <=1080p, H.265/HEVC for 2160p.
# Usage: encode.sh <src> <outdir> <profile> <basename>
set -euo pipefail

SRC="$1"; OUTDIR="$2"; PROFILE="$3"; BASE="$4"

case "$PROFILE" in
  480p)
    HEIGHT=480;  VBR="1000k"; MAXRATE="1200k"; BUFSIZE="2000k"; CODEC="libx264" ;;
  720p)
    HEIGHT=720;  VBR="2800k"; MAXRATE="3200k"; BUFSIZE="5600k"; CODEC="libx264" ;;
  1080p)
    HEIGHT=1080; VBR="5000k"; MAXRATE="5500k"; BUFSIZE="10000k"; CODEC="libx264" ;;
  2160p)
    HEIGHT=2160; VBR="14000k"; MAXRATE="16000k"; BUFSIZE="28000k"; CODEC="libx265" ;;
  *)
    echo "unknown profile: $PROFILE" >&2; exit 2 ;;
esac

OUT="${OUTDIR}/${PROFILE}.mp4"

# -vf scale keeps aspect ratio, forces even dimensions. QVBR-style cap via maxrate.
ffmpeg -y -i "$SRC" \
  -c:v "$CODEC" -preset medium -b:v "$VBR" -maxrate "$MAXRATE" -bufsize "$BUFSIZE" \
  -vf "scale=-2:${HEIGHT}" \
  -c:a aac -b:a 128k -movflags +faststart \
  "$OUT"

# One thumbnail per rendition (first keyframe ~1s in).
ffmpeg -y -ss 00:00:01 -i "$SRC" -vframes 1 -vf "scale=-2:${HEIGHT}" \
  "${OUTDIR}/${PROFILE}-thumb.jpg"

echo "encoded $OUT"
