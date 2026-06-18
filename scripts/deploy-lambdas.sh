#!/usr/bin/env bash
# Package and update Lambda functions.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"

zip -j /tmp/lambda-validator.zip src/lambda-validator.py
zip -j /tmp/lambda-callback.zip src/lambda-callback.py

aws lambda update-function-code \
  --function-name media-engine-validator \
  --zip-file fileb:///tmp/lambda-validator.zip \
  --region "$REGION"

aws lambda update-function-code \
  --function-name media-engine-callback \
  --zip-file fileb:///tmp/lambda-callback.zip \
  --region "$REGION"

echo "Lambda functions updated."
