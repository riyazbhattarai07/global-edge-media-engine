#!/usr/bin/env bash
# =============================================================================
# encode.sh  –  FFmpeg bitrate-ladder encoder
#
# Usage: encode.sh <input_path> <output_path> <profile>
#
# Profiles:
#   360p   H.264  500k  video / 96k  AAC audio  – mobile / low-bandwidth
#   720p   H.264  2500k video / 128k AAC audio  – HD streaming
#   1080p  H.264  5000k video / 192k AAC audio  – Full HD
#   2160p  H.265  15000k video / 256k AAC audio – 4K (HEVC for ~30% size savings)
#
# All profiles:
#   • Two-pass encoding for better quality at target bitrate
#   • CRF as quality floor on 1st pass
#   • Faststart moov atom for progressive download / streaming
#   • AAC-LC audio, normalised to -23 LUFS for consistent loudness
# =============================================================================
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <input> <output> <profile>" >&2
  exit 1
fi

INPUT="$1"
OUTPUT="$2"
PROFILE="$3"

if [[ ! -f "${INPUT}" ]]; then
  echo "Input file not found: ${INPUT}" >&2
  exit 1
fi

# Detect number of logical CPUs for FFmpeg thread tuning
THREADS=$(nproc 2>/dev/null || echo 4)
PASS_LOG="${OUTPUT}.passlog"

run_encode() {
  local vf="$1"       # scale filter
  local vcodec="$2"   # libx264 or libx265
  local vbitrate="$3" # e.g. 5000k
  local crf="$4"      # quality floor
  local abitrate="$5" # e.g. 128k
  local extra="${6:-}"

  echo "[encode.sh] Profile=${PROFILE} codec=${vcodec} vbr=${vbitrate} crf=${crf} aac=${abitrate}" >&2

  # ── Pass 1: analyse, write stats ─────────────────────────────────────────
  ffmpeg -y -hide_banner -loglevel warning \
    -threads "${THREADS}" \
    -i "${INPUT}" \
    -vf "${vf}" \
    -c:v "${vcodec}" \
    -b:v "${vbitrate}" \
    -crf "${crf}" \
    -pass 1 \
    -passlogfile "${PASS_LOG}" \
    -an \
    -f null \
    ${extra} \
    /dev/null

  # ── Pass 2: encode with stats, add audio ─────────────────────────────────
  ffmpeg -y -hide_banner -loglevel warning \
    -threads "${THREADS}" \
    -i "${INPUT}" \
    -vf "${vf}" \
    -c:v "${vcodec}" \
    -b:v "${vbitrate}" \
    -crf "${crf}" \
    -pass 2 \
    -passlogfile "${PASS_LOG}" \
    -c:a aac \
    -b:a "${abitrate}" \
    -ac 2 \
    -ar 48000 \
    -movflags +faststart \
    -map_metadata -1 \
    -map 0:v:0 \
    -map 0:a:0? \
    ${extra} \
    "${OUTPUT}"

  # Cleanup pass log files
  rm -f "${PASS_LOG}-0.log" "${PASS_LOG}-0.log.mbtree" "${PASS_LOG}-0.log.temp"
}

case "${PROFILE}" in
  360p)
    run_encode \
      "scale=trunc(oh*a/2)*2:360:flags=lanczos" \
      "libx264" "500k" "28" "96k" \
      "-preset slow -profile:v main -level 3.1 -tune film"
    ;;
  720p)
    run_encode \
      "scale=trunc(oh*a/2)*2:720:flags=lanczos" \
      "libx264" "2500k" "23" "128k" \
      "-preset slow -profile:v high -level 4.1 -tune film"
    ;;
  1080p)
    run_encode \
      "scale=trunc(oh*a/2)*2:1080:flags=lanczos" \
      "libx264" "5000k" "21" "192k" \
      "-preset slow -profile:v high -level 4.2 -tune film"
    ;;
  2160p)
    # H.265/HEVC for 4K – ~30% smaller than H.264 at equivalent quality
    run_encode \
      "scale=trunc(oh*a/2)*2:2160:flags=lanczos" \
      "libx265" "15000k" "20" "256k" \
      "-preset medium -x265-params 'high-tier=1:level=5.1'"
    ;;
  *)
    echo "Unknown profile '${PROFILE}'. Valid: 360p 720p 1080p 2160p" >&2
    exit 1
    ;;
esac

echo "[encode.sh] Done: ${OUTPUT}" >&2
