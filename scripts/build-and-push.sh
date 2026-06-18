#!/usr/bin/env bash
# Build the FFmpeg encoder image and push to ECR.
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/media-engine-encoder"

aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

docker build -t media-engine-encoder ecs/
docker tag media-engine-encoder:latest "$ECR_REPO:latest"
docker push "$ECR_REPO:latest"
echo "Pushed: $ECR_REPO:latest"
