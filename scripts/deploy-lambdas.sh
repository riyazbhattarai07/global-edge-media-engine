#!/usr/bin/env bash
# Package and update Lambda functions. Run after terraform apply.
set -euo pipefail

PROJECT="${PROJECT:-media-engine}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
mkdir -p "$BUILD"

for fn in validator callback; do
  src="$ROOT/src/lambda-${fn}.py"
  zip="$BUILD/${fn}.zip"
  echo "==> packaging lambda-$fn"
  ( cd "$(dirname "$src")" && zip -q "$zip" "$(basename "$src")" )

  echo "==> updating $PROJECT-$fn"
  aws lambda update-function-code \
    --function-name "$PROJECT-$fn" \
    --zip-file "fileb://$zip" >/dev/null
done

echo "Done."
