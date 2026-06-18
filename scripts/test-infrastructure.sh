#!/usr/bin/env bash
# Post-deploy smoke test: verify buckets, cluster, ECR, etc.
set -euo pipefail

echo "== Buckets =="
aws s3 ls | grep media-engine

echo
echo "== ECS cluster =="
CLUSTER=$(aws ecs list-clusters --query 'clusterArns[0]' --output text)
aws ecs describe-clusters --clusters "$CLUSTER" --query 'clusters[0].[clusterName,status]'

echo
echo "== ECR repository =="
aws ecr describe-repositories --query 'repositories[?contains(repositoryName, `media-engine`)].repositoryUri' --output table

echo
echo "== CloudFront distribution =="
aws cloudfront list-distributions --query 'DistributionList.Items[0].[DomainName,Status]' --output table

echo
echo "== Upload a test video: =="
INPUT_BUCKET=$(aws s3 ls | grep media-engine-input | awk '{print $3}')
echo "aws s3 cp sample-video.mp4 s3://$INPUT_BUCKET/uploads/"
