# Deployment

## Prerequisites

- Terraform >= 1.5, AWS CLI >= 2.0, Docker
- An S3 bucket + DynamoDB table for remote state
- GitHub secrets configured: `AWS_ROLE_ARN`, `TF_STATE_BUCKET`

## Step 1: Backend

```bash
aws s3api create-bucket \
  --bucket terraform-state-media-engine-$(whoami) \
  --region us-east-1

aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

## Step 2: Configure

```bash
cd terraform/media-engine
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars as needed (profiles, Spot vs on-demand, etc.)
```

## Step 3: Deploy Infrastructure

```bash
terraform init -backend-config="bucket=terraform-state-media-engine-$(whoami)"
terraform plan -out=tfplan
terraform apply tfplan
terraform output -json > outputs.json
```

## Step 4: Build & Push the Encoder Image

```bash
cd ../..
./scripts/build-and-push.sh
```

This builds the FFmpeg container and pushes it to ECR. Terraform created the ECR repository; this step populates it.

## Step 5: Smoke Test

```bash
./scripts/test-infrastructure.sh
```

Verify buckets, ECS cluster, ECR, and CloudFront are live.

## Step 6: Upload a Test Video

```bash
INPUT_BUCKET=$(terraform output -raw input_bucket)
aws s3 cp sample-video.mp4 s3://$INPUT_BUCKET/uploads/

# Watch logs
aws logs tail /ecs/media-engine-encoder --follow
```

## Tear Down

```bash
cd terraform/media-engine
terraform destroy
```

Terraform will fail on the ECR repository if it contains images; either delete images first or use `force_destroy = true` in the repository resource.

## CI/CD Setup

The GitHub Actions workflows assume these secrets in your repo:

```
AWS_ROLE_ARN         # ARN of an IAM role trusted by GitHub OIDC
TF_STATE_BUCKET      # Name of your remote state bucket
```

The workflows use OIDC federation, so no long-lived AWS keys are stored.

## Customization

### Change encoding profiles

Edit `terraform.tfvars`:

```hcl
encoding_profiles = ["480p", "720p", "1080p", "2160p"]  # add 4K
```

Then update `ecs/encode.sh` if you add new profiles.

### Switch from Spot to on-demand Fargate

```hcl
use_fargate_spot = false
```

This costs ~3x more but removes interruption risk.

### Increase Fargate task size

```hcl
task_cpu    = 4096  # 4 vCPU
task_memory = 8192  # 8 GB
```

Larger tasks encode faster but cost more per hour.
