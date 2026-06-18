#!/usr/bin/env bash
cat << 'TXT'
=== Illustrative monthly cost (us-east-1, list price) ===

For a demo with occasional encoding (a few short clips):
  Fargate Spot (FFmpeg)   ~$0.50   (a few minutes of compute)
  S3 storage              ~$0.10   (test files)
  CloudFront              $0       (free-tier egress)
  Misc (logs, alarms)     ~$1–2
  ------------------------------------------------
  Total                   ~$2–3/month

For light regular testing (1–2 hours of source/month):
  Fargate Spot            ~$5–10
  S3 storage              ~$0.50
  CloudFront              $0
  Misc                    ~$2
  ------------------------------------------------
  Total                   ~$8–12/month

For production (10+ source-hours/month):
  Fargate Spot            ~$20–50
  S3 storage              ~$2–5
  CloudFront egress       varies (free tier covers 1 TB/mo)
  Misc                    ~$5
  ------------------------------------------------
  Total                   ~$30–60/month (before CDN egress)

Cost drivers:
  1. Fargate task CPU/memory (2048 CPU, 4096 MiB = ~$0.08/hr on Spot)
  2. Fargate runtime per video (linearly with encoding time)
  3. 4K HEVC is 2–3x more expensive than 1080p H.264

Cost levers:
  - Drop 4K from the default build
  - Use Fargate Spot (always on; ~70% off on-demand)
  - Smaller/shorter source videos for testing
  - CloudFront free tier covers all realistic demo traffic

Always verify current pricing at aws.amazon.com/pricing/
TXT
