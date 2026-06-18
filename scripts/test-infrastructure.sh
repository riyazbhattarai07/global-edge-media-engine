#!/usr/bin/env bash
# Post-deploy smoke test: verify buckets, cluster, ECR, etc.
set -euo pipefail

echo '== Buckets =='
aws s3 ls | grep media-engine

echo '== ECS Cluster =='
aws ecs list-clusters | grep media-engine

echo '== ECR =='
aws ecr describe-repositories --repository-names media-engine-encoder --query 'repositories[0].repositoryUri' --output text

echo '== All checks passed =='
