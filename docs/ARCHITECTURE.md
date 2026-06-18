# Architecture

## Overview

The media engine is an event-driven, serverless video processing pipeline:

1. **Upload** — Client uploads via S3 presigned URL to the input bucket.
2. **Validate** — S3 ObjectCreated event triggers a Lambda validator.
3. **Orchestrate** — Validator starts a Step Functions state machine with the list of renditions.
4. **Encode** — Step Functions launches one Fargate Spot task **per rendition in parallel**, each running FFmpeg.
5. **Store** — Outputs land in S3, which auto-transitions to Glacier after 30 days.
6. **Deliver** — CloudFront serves the outputs globally with Origin Shield for a high cache hit ratio.
7. **Notify** — On completion, a callback Lambda publishes a summary to SNS.

## Why FFmpeg-on-Fargate instead of AWS Elemental MediaConvert

**MediaConvert** is billed per normalized output minute, with multipliers for 4K and HEVC — excellent for broadcast-grade OTT workflows but expensive to leave running or to use for small batches. A short test clip across four renditions costs $4–6 with MediaConvert; the same clip on Fargate Spot costs cents.

**FFmpeg-on-Fargate** trades a managed encoding service for fine-grained cost control and the ability to tune the bitrate ladder. The cost model is pure compute time: ~$0.08/hour on Fargate Spot for a 2-vCPU / 4GB task, so a 10-minute source encode across three profiles costs ~$0.02–0.05.

**When to flip the decision:** At sustained high volume (1000+ output hours/month or a need for DRM, certified HDR, or broadcast-grade SLAs), MediaConvert's reserved slots, managed scaling, and reliability features outweigh the per-minute cost. Below that, Fargate stays cheaper and more flexible.

## Data Flow

```
S3 Input (uploads/) 
  ↓ (ObjectCreated event)
EventBridge
  ↓ (route to validator)
Lambda Validator
  ↓ (starts execution)
Step Functions
  ├→ [Parallel] Fargate task (480p)
  ├→ [Parallel] Fargate task (720p)
  ├→ [Parallel] Fargate task (1080p)
  └→ (all tasks complete)
S3 Output (renditions + Glacier)
  ↓
CloudFront (cache + Origin Shield)
  ↓
Global users
```

## Key Design Choices

### Spot Fargate for encode tasks
Spot is ~70% cheaper than on-demand and interruptions are rare for short-lived tasks. Step Functions retries on Spot interruption, so transient failures are handled gracefully.

### Parallel execution across profiles
Each rendition encodes independently, so a 4-profile pipeline with typical source runtime takes ~as long as one sequential encode instead of 4×. Step Functions Map iterator handles the parallelism.

### Public subnets + IGW for compute (no NAT)
Encoder tasks need egress to S3, ECR, and CloudWatch. Using public subnets with an IGW costs $0/mo (NAT gateway would add ~$30/mo and $0.04 per GB processed). For a hardened variant, swap to private subnets + VPC interface endpoints (ecr.api, ecr.dkr, logs, s3 gateway).

### CloudFront Origin Shield
Adds ~$0.005 per request but raises the cache hit ratio from ~80% to ~95%, cutting origin load and S3 transfer costs. The trade-off is positive for video delivery.

### S3 Intelligent-Tiering + Glacier transition
Automatically moves cold files to cheaper storage tiers. Outputs default to a 30-day transition to Glacier to keep warm files cached and cold archives cheap.

### Container per rendition
One Fargate task per profile means the encoder container is simple — it pulls the source, runs FFmpeg with pre-baked profile settings, and uploads the result. No orchestration inside the container.

## Security

- **Private S3 buckets** with public-access blocked.
- **IAM least privilege:** each component has exactly the permissions it needs.
- **No static credentials:** GitHub Actions uses OIDC federation.
- **VPC isolation:** encoder tasks can't reach the internet (public subnet for egress only); no inbound rules.
- **Encryption at rest** on S3 and CloudFront.
- **HTTPS/TLS 1.2+** on CloudFront.

## Monitoring

- **CloudWatch logs** from each encoder task, aggregated under `/ecs/media-engine-encoder`.
- **Step Functions execution logs** under `/aws/vendedlogs/states/media-engine`.
- **Metrics:** execution count, success/failure rate, task durations.
- **Alarms:** SNS notification on pipeline failures.
- **Dashboard:** execution history and encoder log tails.

## Gotchas and Extensions

**Spot interruptions:** Very rare (~2%) for short-lived tasks, but Step Functions retry handles them. Monitor retries in the CloudWatch metrics if this becomes a concern.

**FFmpeg tuning:** The bitrate ladder in `ecs/encode.sh` is a default starting point. Real encoding benefits from testing on your actual source material and your target delivery platforms.

**Cold starts:** Lambda cold starts add ~1s; encoder Fargate tasks add ~10–15s (image pull + container startup). For a pipeline you run multiple times per day, this is fine. For high-throughput, consider warming pools.

**MediaConvert path:** To swap back to MediaConvert, replace the ECS task definitions with a MediaConvert API call in Step Functions and remove the ECR/Fargate complexity. The architecture survives the swap.

## Cost Optimization Checklist

- [ ] Use `use_fargate_spot = true` (default, ~70% savings)
- [ ] Limit encoding profiles to what you actually need (4K is optional)
- [ ] Test with short video clips (~1–2 min) before full encodes
- [ ] Confirm CloudFront free-tier egress covers your delivery
- [ ] Monitor Fargate task durations; if consistently running over 10 min, right-size CPU/memory
- [ ] Turn off Intelligent-Tiering if you don't have cold archive access patterns
