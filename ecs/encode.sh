#!/usr/bin/env bash
# Per-profile FFmpeg bitrate ladder. H.264 for <=1080p, H.265/HEVC for 2160p.
# Usage: encode.sh <source> <output> <profile>
set -euo pipefail

SOURCE="$1"
OUTPUT="$2"
PROFILE="$3"

case "$PROFILE" in
  360p)  ffmpeg -i "$SOURCE" -vf scale=-2:360  -c:v libx264 -b:v 500k  -c:a aac -b:a 96k  "$OUTPUT" ;;
  720p)  ffmpeg -i "$SOURCE" -vf scale=-2:720  -c:v libx264 -b:v 2500k -c:a aac -b:a 128k "$OUTPUT" ;;
  1080p) ffmpeg -i "$SOURCE" -vf scale=-2:1080 -c:v libx264 -b:v 5000k -c:a aac -b:a 192k "$OUTPUT" ;;
  2160p) ffmpeg -i "$SOURCE" -vf scale=-2:2160 -c:v libx265 -b:v 15000k -c:a aac -b:a 256k "$OUTPUT" ;;
  *) echo "Unknown profile: $PROFILE" && exit 1 ;;
esac
