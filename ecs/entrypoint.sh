#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh  –  ECS Fargate encoder task entry point
#
# Flow:
#   1. Validate required environment variables
#   2. Download source video from S3
#   3. Run FFmpeg encoding for the requested PROFILE
#   4. Extract output metadata (duration, size, codec)
#   5. Upload encoded rendition to output S3 bucket
#   6. Tag the output object with encoding metadata
#   7. Report success/failure to Step Functions via TASK_TOKEN (if provided)
#
# Required env vars (injected by Step Functions ECS RunTask parameters):
#   INPUT_BUCKET   – source S3 bucket
#   INPUT_KEY      – source S3 object key
#   OUTPUT_BUCKET  – destination S3 bucket
#   PROFILE        – encoding profile: 360p | 720p | 1080p | 2160p
#   TASK_TOKEN     – Step Functions task token for .waitForTaskToken callback
#
# Optional:
#   AWS_DEFAULT_REGION  – defaults to us-east-1
#   LOG_LEVEL           – DEBUG | INFO | WARN | ERROR (default INFO)
# =============================================================================
set -euo pipefail

# ── Logging helpers ───────────────────────────────────────────────────────────
LOG_LEVEL="${LOG_LEVEL:-INFO}"
TIMESTAMP() { date -u "+%Y-%m-%dT%H:%M:%SZ"; }
log()  { echo "[$(TIMESTAMP)] [INFO]  $*" >&2; }
warn() { echo "[$(TIMESTAMP)] [WARN]  $*" >&2; }
error(){ echo "[$(TIMESTAMP)] [ERROR] $*" >&2; }
debug(){
  if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
    echo "[$(TIMESTAMP)] [DEBUG] $*" >&2
  fi
}

# ── Step Functions callback helpers ───────────────────────────────────────────
sfn_succeed() {
  local output="$1"
  if [[ -n "${TASK_TOKEN:-}" ]]; then
    log "Sending task success to Step Functions..."
    aws stepfunctions send-task-success \
      --task-token "${TASK_TOKEN}" \
      --task-output "${output}" \
      --region "${AWS_DEFAULT_REGION:-us-east-1}"
  fi
}

sfn_fail() {
  local cause="$1"
  local error_code="${2:-EncoderError}"
  if [[ -n "${TASK_TOKEN:-}" ]]; then
    warn "Sending task failure to Step Functions: ${cause}"
    aws stepfunctions send-task-failure \
      --task-token "${TASK_TOKEN}" \
      --cause "${cause}" \
      --error "${error_code}" \
      --region "${AWS_DEFAULT_REGION:-us-east-1}" || true
  fi
  exit 1
}

# ── Cleanup trap ──────────────────────────────────────────────────────────────
TMP_DIR=""
cleanup() {
  local exit_code=$?
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    debug "Cleaning up temp dir: ${TMP_DIR}"
    rm -rf "${TMP_DIR}"
  fi
  if [[ ${exit_code} -ne 0 ]]; then
    sfn_fail "Encoder exited with code ${exit_code}" "EncoderFailed"
  fi
}
trap cleanup EXIT

# ── Validate required variables ───────────────────────────────────────────────
log "=== Media Engine Encoder Starting ==="
log "Profile: ${PROFILE:-<not set>}"

for var in INPUT_BUCKET INPUT_KEY OUTPUT_BUCKET PROFILE; do
  if [[ -z "${!var:-}" ]]; then
    error "Required environment variable '${var}' is not set."
    sfn_fail "Missing environment variable: ${var}" "ConfigurationError"
  fi
done

# Validate profile value
case "${PROFILE}" in
  360p|720p|1080p|2160p) ;;
  *)
    error "Unknown PROFILE '${PROFILE}'. Must be 360p, 720p, 1080p, or 2160p."
    sfn_fail "Invalid profile: ${PROFILE}" "ConfigurationError"
    ;;
esac

# ── Set up temp directory ─────────────────────────────────────────────────────
TMP_DIR=$(mktemp -d /tmp/encoder-XXXXXX)
FILENAME=$(basename "${INPUT_KEY}")
BASENAME="${FILENAME%.*}"
EXTENSION="${FILENAME##*.}"

INPUT_PATH="${TMP_DIR}/input.${EXTENSION}"
OUTPUT_FILENAME="${BASENAME}_${PROFILE}.mp4"
OUTPUT_PATH="${TMP_DIR}/${OUTPUT_FILENAME}"

log "Temp dir: ${TMP_DIR}"
log "Input:    s3://${INPUT_BUCKET}/${INPUT_KEY}"
log "Output:   s3://${OUTPUT_BUCKET}/encoded/${PROFILE}/${OUTPUT_FILENAME}"

# ── Download source video ─────────────────────────────────────────────────────
log "Downloading source video..."
START_DOWNLOAD=$(date +%s)

aws s3 cp \
  "s3://${INPUT_BUCKET}/${INPUT_KEY}" \
  "${INPUT_PATH}" \
  --no-progress \
  --region "${AWS_DEFAULT_REGION:-us-east-1}" \
  || sfn_fail "Failed to download s3://${INPUT_BUCKET}/${INPUT_KEY}" "S3DownloadError"

DOWNLOAD_DURATION=$(( $(date +%s) - START_DOWNLOAD ))
INPUT_SIZE=$(stat -c%s "${INPUT_PATH}")
log "Downloaded ${INPUT_SIZE} bytes in ${DOWNLOAD_DURATION}s"

# ── Probe source metadata ─────────────────────────────────────────────────────
log "Probing source metadata..."
SOURCE_INFO=$(ffprobe -v quiet -print_format json -show_streams -show_format \
  "${INPUT_PATH}" 2>/dev/null || echo '{}')
SOURCE_DURATION=$(echo "${SOURCE_INFO}" | jq -r '.format.duration // "unknown"')
SOURCE_WIDTH=$(echo "${SOURCE_INFO}"    | jq -r '.streams[] | select(.codec_type=="video") | .width  // "?"' | head -1)
SOURCE_HEIGHT=$(echo "${SOURCE_INFO}"   | jq -r '.streams[] | select(.codec_type=="video") | .height // "?"' | head -1)
debug "Source: ${SOURCE_WIDTH}x${SOURCE_HEIGHT}, duration=${SOURCE_DURATION}s"

# ── Encode ────────────────────────────────────────────────────────────────────
log "Starting FFmpeg encode (profile: ${PROFILE})..."
START_ENCODE=$(date +%s)

/app/encode.sh "${INPUT_PATH}" "${OUTPUT_PATH}" "${PROFILE}" \
  || sfn_fail "FFmpeg encoding failed for profile ${PROFILE}" "EncodeError"

ENCODE_DURATION=$(( $(date +%s) - START_ENCODE ))
OUTPUT_SIZE=$(stat -c%s "${OUTPUT_PATH}")
log "Encoded in ${ENCODE_DURATION}s → output: ${OUTPUT_SIZE} bytes"

# Probe output codec for reporting
OUTPUT_CODEC=$(ffprobe -v quiet -select_streams v:0 \
  -show_entries stream=codec_name \
  -of default=noprint_wrappers=1:nokey=1 \
  "${OUTPUT_PATH}" 2>/dev/null || echo "unknown")

# ── Upload to S3 ──────────────────────────────────────────────────────────────
OUTPUT_KEY="encoded/${PROFILE}/${OUTPUT_FILENAME}"
log "Uploading to s3://${OUTPUT_BUCKET}/${OUTPUT_KEY}..."
START_UPLOAD=$(date +%s)

aws s3 cp \
  "${OUTPUT_PATH}" \
  "s3://${OUTPUT_BUCKET}/${OUTPUT_KEY}" \
  --content-type "video/mp4" \
  --no-progress \
  --region "${AWS_DEFAULT_REGION:-us-east-1}" \
  || sfn_fail "Failed to upload to s3://${OUTPUT_BUCKET}/${OUTPUT_KEY}" "S3UploadError"

UPLOAD_DURATION=$(( $(date +%s) - START_UPLOAD ))
log "Uploaded in ${UPLOAD_DURATION}s"

# ── Tag the output object ─────────────────────────────────────────────────────
aws s3api put-object-tagging \
  --bucket "${OUTPUT_BUCKET}" \
  --key "${OUTPUT_KEY}" \
  --tagging "TagSet=[\
    {Key=profile,Value=${PROFILE}},\
    {Key=source_key,Value=${INPUT_KEY}},\
    {Key=encode_duration_s,Value=${ENCODE_DURATION}},\
    {Key=codec,Value=${OUTPUT_CODEC}}\
  ]" \
  --region "${AWS_DEFAULT_REGION:-us-east-1}" || warn "Failed to tag output object (non-fatal)"

# ── Report success ────────────────────────────────────────────────────────────
log "=== Encoding complete ==="
log "Profile: ${PROFILE} | Output: ${OUTPUT_KEY} | Size: ${OUTPUT_SIZE} bytes | Encode time: ${ENCODE_DURATION}s"

OUTPUT_JSON=$(jq -cn \
  --arg profile         "${PROFILE}" \
  --arg status          "succeeded" \
  --arg output_key      "${OUTPUT_KEY}" \
  --argjson output_size  ${OUTPUT_SIZE} \
  --arg codec           "${OUTPUT_CODEC}" \
  --argjson encode_dur   ${ENCODE_DURATION} \
  --argjson input_size   ${INPUT_SIZE} \
  '{
    profile:               $profile,
    status:                $status,
    output_key:            $output_key,
    output_size_bytes:     $output_size,
    codec:                 $codec,
    encoding_duration_s:   $encode_dur,
    input_size_bytes:      $input_size
  }'
)

sfn_succeed "${OUTPUT_JSON}"
