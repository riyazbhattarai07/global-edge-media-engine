#!/usr/bin/env bash
# Pulls the source from S3, runs the per-profile FFmpeg encode, and uploads
# the rendition (+ a thumbnail) to the output bucket.
#
# Required env (set by Step Functions container overrides):
#   INPUT_BUCKET, INPUT_KEY, PROFILE, OUTPUT_BUCKET
set -euo pipefail

: "${INPUT_BUCKET:?}" "${INPUT_KEY:?}" "${PROFILE:?}" "${OUTPUT_BUCKET:?}"

BASENAME="$(basename "${INPUT_KEY%.*}")"
SRC="/work/source"
OUTDIR="/work/out"
mkdir -p "$OUTDIR"

echo "[encoder] downloading s3://${INPUT_BUCKET}/${INPUT_KEY}"
aws s3 cp "s3://${INPUT_BUCKET}/${INPUT_KEY}" "$SRC"

echo "[encoder] encoding profile=${PROFILE}"
/usr/local/bin/encode.sh "$SRC" "$OUTDIR" "$PROFILE" "$BASENAME"

DEST="s3://${OUTPUT_BUCKET}/${BASENAME}/"
echo "[encoder] uploading outputs to ${DEST}"
aws s3 cp "$OUTDIR/" "$DEST" --recursive

echo "[encoder] done: ${BASENAME} (${PROFILE})"
