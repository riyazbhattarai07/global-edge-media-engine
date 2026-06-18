#!/usr/bin/env bash
# Build the FFmpeg encoder image and push to ECR.
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_NAME="media-engine-encoder"
REPO_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}"

echo "==> Authenticating ECR"
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$REPO_URI"

echo "==> Building image"
docker build -t "${REPO_NAME}:latest" ecs/

echo "==> Tagging for ECR"
docker tag "${REPO_NAME}:latest" "${REPO_URI}:latest"

echo "==> Pushing to $REPO_URI"
docker push "${REPO_URI}:latest"

echo "Done. Image: ${REPO_URI}:latest"
