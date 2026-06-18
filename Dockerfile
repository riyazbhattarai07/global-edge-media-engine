# Troubleshooting

## Encoder task doesn't start

Check that the FFmpeg image is in ECR and correctly tagged:

```bash
aws ecr describe-repositories --repository-names media-engine-encoder
aws ecr describe-images --repository-name media-engine-encoder
```

If empty, run `./scripts/build-and-push.sh`.

## Task exits immediately with non-zero status

Check the ECS task logs:

```bash
aws logs tail /ecs/media-engine-encoder --follow
```

Common issues:
- **S3 permissions:** The task role doesn't have `s3:GetObject` or `s3:PutObject`.
- **Missing env vars:** INPUT_BUCKET, INPUT_KEY, PROFILE not set by Step Functions.
- **FFmpeg missing or incompatible:** The Dockerfile includes `ffmpeg` via apt; confirm the image build succeeded.

## Step Functions execution fails

```bash
aws stepfunctions list-executions --state-machine-arn <arn> --status-filter FAILED
aws stepfunctions describe-execution --execution-arn <arn>
aws logs tail /aws/vendedlogs/states/media-engine --follow
```

Check the "executionFailureDetails" field. Common failures:
- **Spot interruption:** Visible as `TASK_FAILED`. Retries handle this automatically (3x by default).
- **IAM permission:** Check the Step Functions role has `ecs:RunTask`, `iam:PassRole`, etc.
- **Subnet/security group misconfiguration:** EC2 describe-instances won't show the task if the subnet is full or the SG blocks egress.

## CloudFront returning 403

```bash
curl -I https://<cdn-domain>/video.mp4 | grep -i x-amzn-errortype
```

If "AccessDenied," the bucket policy doesn't allow CloudFront. Verify:

```bash
aws s3api get-bucket-policy --bucket <output-bucket>
```

Should include the CloudFront distribution OAC principal.

## Output files not visible in S3

- Check the encoder task logs for ffmpeg errors.
- Confirm the OUTPUT_BUCKET env var matches the actual bucket name.
- Verify the task role has `s3:PutObject` on the output bucket.

## Lambda validator doesn't trigger on upload

Confirm EventBridge rule exists and is enabled:

```bash
aws events list-rules --name-prefix media-engine
aws events list-targets-by-rule --rule <rule-name>
```

Check that the rule's event pattern matches your upload key prefix:

```bash
aws events describe-rule --name <rule-name>
```

It should filter on `detail.object.key[0].prefix: "uploads/"`.

## High costs due to Fargate on-demand

Verify the cluster is using Spot:

```bash
aws ecs list-clusters
aws ecs describe-clusters --clusters <cluster-arn> --query 'clusters[0].capacityProviders'
```

If only "FARGATE" is listed, switch to Spot in `terraform.tfvars` and re-apply:

```hcl
use_fargate_spot = true
```

## Poor CloudFront cache hit ratio

Check Origin Shield is enabled:

```bash
aws cloudfront get-distribution-config --id <dist-id> | grep -i origin
```

If cache hits are still low, the output bucket's Cache-Control headers may be too restrictive. Edit the distribution to set a longer default TTL.

## I/O errors during encoding

If you see "Disk I/O error" in logs, the Fargate task's ephemeral storage may be full. Increase `task_memory` (ephemeral storage scales with memory) or reduce the video size.
