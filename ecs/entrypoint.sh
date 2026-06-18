#!/usr/bin/env bash
# Pulls the source from S3, runs the per-profile FFmpeg encode, and uploads
# the rendition to the output bucket.
set -euo pipefail

INPUT_BUCKET="${INPUT_BUCKET}"
INPUT_KEY="${INPUT_KEY}"
OUTPUT_BUCKET="${OUTPUT_BUCKET}"
PROFILE="${PROFILE}"

TMP_INPUT="/tmp/input_$(basename $INPUT_KEY)"
TMP_OUTPUT="/tmp/output_${PROFILE}_$(basename $INPUT_KEY)"

echo "Downloading s3://$INPUT_BUCKET/$INPUT_KEY"
aws s3 cp "s3://$INPUT_BUCKET/$INPUT_KEY" "$TMP_INPUT"

echo "Encoding profile: $PROFILE"
/app/encode.sh "$TMP_INPUT" "$TMP_OUTPUT" "$PROFILE"

OUTPUT_KEY="encoded/${PROFILE}/$(basename $INPUT_KEY)"
echo "Uploading to s3://$OUTPUT_BUCKET/$OUTPUT_KEY"
aws s3 cp "$TMP_OUTPUT" "s3://$OUTPUT_BUCKET/$OUTPUT_KEY"

echo "Done: s3://$OUTPUT_BUCKET/$OUTPUT_KEY"
