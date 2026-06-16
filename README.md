# 🎬 Global Edge-Accelerated Media Engine

[![Terraform](https://img.shields.io/badge/Terraform-v1.5+-623CE4?style=flat-square&logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Serverless-FF9900?style=flat-square&logo=amazon-aws)](https://aws.amazon.com/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-Automated-2088F0?style=flat-square&logo=github-actions)](https://github.com/features/actions)

A globally-distributed video processing platform built on serverless AWS services. It ingests uploaded video, validates and orchestrates encoding into multiple delivery profiles, and serves the output worldwide through a CDN — all defined as infrastructure-as-code and deployed through CI/CD, with minimal operational overhead.

**Designed for:**
- High CDN cache efficiency via CloudFront Origin Shield (target: 95%+ hit ratio)
- Parallel encoding on auto-scaling Fargate workers (configurable; defaults to 50 concurrent jobs)
- Cost-efficient storage with S3 Intelligent-Tiering and Glacier transition after 30 days
- Smaller output and lower delivery cost using H.265/HEVC (~30% smaller than H.264 at comparable quality)
- Low-latency global delivery through CloudFront

> Performance and cost figures below are design targets and list-price estimates for an illustrative workload, not measured production results. Replace them with your own measurements once you've benchmarked a real run.

---

## 🎯 Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│              USER UPLOAD & INGESTION                     │
│  (S3 presigned upload / CORS-enabled)                    │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
        ┌──────────────┐
        │ S3 Input     │
        │ (7-day TTL)  │
        └──────┬───────┘
               │ (S3:ObjectCreated)
               ▼
        ┌──────────────────┐
        │   EventBridge    │
        │   (Event Router) │
        └──────┬───────────┘
               │
               ▼
        ┌──────────────────┐
        │    Lambda        │
        │   Validator      │
        └──────┬───────────┘
               │
               ▼
        ┌───────────────────────────────┐
        │   Step Functions              │
        │  State Machine Orchestration  │
        └──────┬────────────────────────┘
               │
       ┌───────┴────────┐
       │                │
       ▼                ▼
   ┌─────────┐    ┌──────────────┐
   │MediaConv│    │   Fargate    │
   │  ert    │    │   Workers    │
   │(Encoding)    │ (Thumbnails) │
   └────┬────┘    └──────┬───────┘
        │                │
        └────────┬───────┘
                 │
                 ▼
        ┌──────────────┐
        │ S3 Output    │
        │ (Glacier)    │
        └──────┬───────┘
               │
               ▼
        ┌──────────────────┐
        │  CloudFront CDN  │
        │ (Origin Shield)  │
        └──────┬───────────┘
               │
               ▼
        ┌──────────────────┐
        │  Global Users    │
        │ (Low Latency)    │
        └──────────────────┘
```

---

## 🚀 Quick Start

### Prerequisites
```bash
# Required
- Terraform >= 1.5
- AWS CLI >= 2.0
- Git
```

### 1. Clone & Setup
```bash
git clone https://github.com/riyazbhattarai07/media-engine.git
cd media-engine

# Create S3 backend + DynamoDB lock table
aws s3api create-bucket \
  --bucket terraform-state-media-engine-$(whoami) \
  --region us-east-1

aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
```

### 2. Configure
```bash
cd terraform/media-engine

cat > terraform.tfvars << 'EOF'
aws_region             = "us-east-1"
environment            = "prod"
project_name           = "media-engine"
parallel_encoding_jobs = 50
storage_retention_days = 90
EOF
```

### 3. Deploy
```bash
terraform init \
  -backend-config="bucket=terraform-state-media-engine-$(whoami)" \
  -backend-config="key=media-engine.tfstate" \
  -backend-config="region=us-east-1"

terraform plan -out=tfplan
terraform apply tfplan

# Capture outputs
terraform output -json > outputs.json
```

### 4. Upload a Test Video
```bash
INPUT_BUCKET=$(terraform output -raw input_bucket)

aws s3 cp sample-video.mp4 s3://$INPUT_BUCKET/uploads/

# Follow the pipeline
aws logs tail /aws/stepfunctions/media-engine --follow
```

---

## ⚙️ CI/CD Pipeline (GitHub Actions)

A multi-stage pipeline runs on every push and pull request:

| Stage | Trigger | What it does |
|-------|---------|--------------|
| **Validate** | Every push | `terraform fmt -check`, `terraform validate`, syntax checks |
| **Security** | Every push | TFLint + Checkov scanning, SARIF upload to GitHub Security |
| **Plan** | Pull requests | `terraform plan`, optional cost estimate, results posted as a PR comment |
| **Deploy** | Merge to `main` | Apply infrastructure, update Lambda/ECS, run post-deploy checks |
| **Cost** | Post-plan | Infracost diff and budget tracking |

### Required GitHub Secrets
```
AWS_ROLE_ARN        # AWS OIDC role assumed by the pipeline
INFRACOST_API_KEY   # Optional — enables cost diffing
```

Authentication uses GitHub OIDC federation, so no long-lived AWS keys are stored in the repo.

---

## 💰 Cost Estimate

Illustrative monthly cost for **~1 TB of video processed**, us-east-1, list pricing. Treat as a planning estimate, not a billed figure.

| Component | Est. Cost | Optimization |
|-----------|-----------|--------------|
| S3 Storage | $50 | Intelligent-Tiering + Glacier transition |
| MediaConvert | $400 | Reserved transcode slots for sustained volume |
| Fargate | $150 | Fargate Spot for thumbnail workers (~70% off on-demand) |
| CloudFront | $85 | Origin Shield (trades a small request cost for higher cache efficiency) |
| Lambda | $20 | Right-sized memory |
| Misc (alarms, SNS) | $20 | — |
| **Total** | **~$725/mo** | Scales roughly linearly with volume |

**Cost levers built in:**
- S3 Intelligent-Tiering with automatic Glacier transition after 30 days
- H.265/HEVC encoding (~30% smaller output than H.264)
- CloudFront Origin Shield to raise cache hit ratio and cut origin fetches
- Fargate Spot for interruptible thumbnail generation

---

## 📁 Project Structure

```
media-engine/
├── .github/
│   └── workflows/
│       ├── terraform-validate.yml
│       ├── terraform-plan.yml
│       ├── terraform-deploy.yml
│       └── lambda-deploy.yml
├── terraform/
│   └── media-engine/
│       ├── main.tf               # All infrastructure
│       ├── terraform.tfvars      # Variables
│       └── outputs.tf            # Outputs
├── src/
│   ├── lambda-validator.py       # Input validation
│   ├── lambda-callback.py        # Encoding callback
│   └── requirements.txt          # Python deps
├── ecs/
│   ├── Dockerfile                # FFmpeg container
│   └── entrypoint.sh             # Task script
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEPLOYMENT.md
│   └── TROUBLESHOOTING.md
├── scripts/
│   ├── deploy-lambdas.sh
│   ├── test-infrastructure.sh
│   └── cost-estimate.sh
├── tests/
│   ├── unit/
│   ├── integration/
│   └── load/
├── README.md
├── LICENSE
└── .gitignore
```

---

## 🔄 Processing Workflow

**Upload** — Client uploads via an S3 presigned URL; the `ObjectCreated` event is routed by EventBridge to the validator Lambda.

**Validate** — Lambda checks format, codec, and resolution, extracts metadata, and starts the Step Functions execution.

**Encode** — Step Functions invokes MediaConvert to produce four output profiles (480p mobile, 720p tablet, 1080p HD, 2160p 4K) while Fargate workers generate thumbnails in parallel.

**Distribute** — Outputs land in S3, transition to Glacier after 30 days, and are served globally through CloudFront.

**Monitor** — CloudWatch captures per-stage logs and metrics; SNS sends completion and failure notifications.

---

## 🧪 Testing & Validation

```bash
# Upload a test video
INPUT_BUCKET=$(terraform output -raw input_bucket)
aws s3 cp sample-video.mp4 s3://$INPUT_BUCKET/uploads/test.mp4

# Watch encoding
aws logs tail /aws/mediaconvert/media-engine --follow

# Inspect outputs
OUTPUT_BUCKET=$(terraform output -raw output_bucket)
aws s3 ls s3://$OUTPUT_BUCKET/ --recursive

# Invoke the validator directly
aws lambda invoke \
  --function-name media-engine-validator \
  --payload '{"bucket":"...","key":"test.mp4"}' \
  response.json && cat response.json

# Confirm a CloudFront cache hit
CDN=$(terraform output -raw cloudfront_domain)
curl -I https://$CDN/video-name/mobile.mp4 | grep -i x-cache
```

---

## 🔐 Security

**Infrastructure**
- Private subnets for ECS workers (VPC isolation)
- S3 encryption at rest (AES-256)
- CloudFront HTTPS with TLS 1.2+
- Least-privilege IAM, scoped per service
- No static credentials — GitHub OIDC federation only

**Code & pipeline**
- TFLint + Checkov on every push
- Python dependency scanning
- SARIF reports surfaced in GitHub Security

---

## 🧠 What This Project Demonstrates

- **Serverless architecture** — event-driven processing across S3, EventBridge, Lambda, Step Functions, MediaConvert, ECS Fargate, and CloudFront
- **Infrastructure as code** — Terraform with remote state, locking, and outputs
- **CI/CD** — multi-stage GitHub Actions pipeline with OIDC auth, security scanning, and cost estimation
- **Cost-aware design** — tiered storage, Spot compute, codec selection, and CDN caching as deliberate trade-offs
- **Operability** — centralized logging, metrics, and alerting

---

## 🐛 Troubleshooting

**MediaConvert job fails**
```bash
aws mediaconvert list-jobs --status ERROR
aws mediaconvert get-job --id <job-id>
aws iam get-role-policy --role-name media-engine-mediaconvert --policy-name <policy>
```

**CloudFront not caching**
```bash
aws cloudfront create-invalidation --distribution-id <dist-id> --paths "/*"
curl -I https://<cdn-domain>/video.mp4 | grep -i cache-control
```

**S3 lifecycle not triggering**
```bash
aws s3api get-bucket-lifecycle-configuration --bucket <output-bucket>
aws s3api list-objects-v2 --bucket <output-bucket>
```

---

## 🚀 Roadmap

- [ ] Live streaming support
- [ ] AI-assisted quality analysis
- [ ] Multi-region output replication
- [ ] Analytics dashboard
- [ ] DRM integration
- [ ] Custom watermarking

---

## 📄 License

MIT License — see [LICENSE](LICENSE)

---

## 🎯 What I'm Looking For

I'm actively seeking opportunities as a **Cloud Engineer**, **DevOps Engineer**, or **Junior Solutions Architect** where I can:
- Design and implement scalable cloud solutions
- Apply AWS Well-Architected principles in real workloads
- Contribute to infrastructure modernization initiatives
- Optimize cloud cost and performance

<div align="center">

<hr>

**Based in Calgary, AB | Open to relocation within Canada**

<hr>

## 📞 Let's Connect

[![Email](https://img.shields.io/badge/Email-EA4335?style=for-the-badge&logo=gmail&logoColor=white)](mailto:riyabhattarai07@gmail.com)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/riyaz-bhattarai-836ab6323/)
[![Portfolio](https://img.shields.io/badge/Portfolio-000000?style=for-the-badge&logo=vercel&logoColor=white)](https://portfolio-ajpn.vercel.app/)
[![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/riyazbhattarai07)

**💡 Open to interesting projects and collaborations. Feel free to reach out!**

</div>
