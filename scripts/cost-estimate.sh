#!/usr/bin/env bash
cat << 'TXT'
=== Illustrative monthly cost (us-east-1, list price) ===

For a demo with occasional encoding jobs:
  Fargate Spot vCPU: ~$0.01264/vCPU-hr
  Fargate Spot memory: ~$0.00138/GB-hr
  S3 storage: $0.023/GB-month
  CloudFront: $0.0085/GB out
  Step Functions: $0.025/1000 state transitions

TXT
echo "Run 'terraform plan' and review the Infracost output for accurate estimates."
