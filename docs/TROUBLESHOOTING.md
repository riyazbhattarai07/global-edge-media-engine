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
