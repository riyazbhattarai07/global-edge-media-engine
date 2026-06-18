# 🎬 Global Edge-Accelerated Media Engine

[![Terraform](https://img.shields.io/badge/Terraform-v1.5+-623CE4?style=flat-square&logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Serverless-FF9900?style=flat-square&logo=amazon-aws)](https://aws.amazon.com/)
[![FFmpeg](https://img.shields.io/badge/FFmpeg-Encoding-007808?style=flat-square&logo=ffmpeg)](https://ffmpeg.org/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-Automated-2088F0?style=flat-square&logo=github-actions)](https://github.com/features/actions)

A globally-distributed video processing platform built on serverless AWS services. It ingests uploaded video, validates and orchestrates encoding into multiple delivery profiles using **FFmpeg on AWS Fargate (Spot)**, and serves the output worldwide through a CDN — all defined as infrastructure-as-code and deployed through CI/CD, with minimal operational overhead and near-zero idle cost.

**Designed for:**
- Self-managed encoding with **FFmpeg on Fargate Spot** — full control over the bitrate ladder, codecs, and quality settings, billed only for compute time actually used
- High CDN cache efficiency via CloudFront Origin Shield (target: 95%+ hit ratio)
- Parallel encoding across auto-scaling Fargate tasks (configurable concurrency)
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
               │ (one Fargate task per rendition, in parallel)
       ┌───────┼────────────────┬────────────┐
       ▼       ▼                ▼            ▼
   ┌────────┐┌────────┐   ┌──────────┐ ┌──────────────┐
   │FFmpeg  ││FFmpeg  │   │ FFmpeg   │ │  FFmpeg      │
   │480p    ││720p    │   │ 1080p    │ │  thumbnails  │
   │(Fargate)(Fargate)│   │(Fargate) │ │  (Fargate)   │
   └────┬───┘└───┬────┘   └────┬─────┘ └──────┬───────┘
        └────────┴────────┬────┴──────────────┘
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

> **Design decision — FFmpeg on Fargate instead of AWS Elemental MediaConvert.**
> MediaConvert is billed per normalized output minute, with large multipliers for 4K/HEVC — excellent for high-volume, broadcast-grade OTT, but expensive and impossible to leave running cheaply. This build encodes with **FFmpeg in a container on Fargate Spot**, so cost is just compute-time (a few cents per short clip) and idle cost is **$0**. The trade-off is that I own the encoding configuration and Spot-interruption handling rather than getting them managed. For a cost-controlled, self-hostable pipeline that's the right call; the volume threshold where I'd switch back to MediaConvert is documented in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## 🎥 Demo

> _Replace with your recorded walkthrough._ A 3–5 minute screen recording showing: upload → validation → parallel Fargate encoding → output played back through CloudFront, plus the dashboard. This is the fastest way for a reviewer to see the whole pipeline working end-to-end.

`[▶ Watch the walkthrough](LINK_TO_YOUR_DEMO)`

---

## 🚀 Quick Start

### Prerequisites
```bash
# Required
- Terraform >= 1.5
- AWS CLI >= 2.0
- Docker (to build the FFmpeg encoder image)
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
  --billing-mode PAY_PER_REQUEST
```

### 2. Build & push the FFmpeg encoder image
```bash
# ECR repo is created by Terraform; this pushes the encoder container to it
./scripts/build-and-push.sh
```

### 3. Configure
```bash
cd terraform/media-engine

cat > terraform.tfvars << 'EOF'
aws_region             = "us-east-1"
environment            = "demo"
project_name           = "media-engine"
encoding_profiles      = ["480p", "720p", "1080p"]  # add "2160p" for optional 4K
use_fargate_spot       = true
storage_retention_days = 90
EOF
```

### 4. Deploy
```bash
terraform init \
  -backend-config="bucket=terraform-state-media-engine-$(whoami)" \
  -backend-config="key=media-engine.tfstate" \
  -backend-config="region=us-east-1"

terraform plan -out=tfplan
terraform apply tfplan
terraform output -json > outputs.json
```

### 5. Upload a Test Video
```bash
INPUT_BUCKET=$(terraform output -raw input_bucket)
aws s3 cp sample-video.mp4 s3://$INPUT_BUCKET/uploads/

# Follow the orchestration (enable logging on the state machine)
aws logs tail /aws/vendedlogs/states/media-engine --follow
```

### 6. Tear down (optional — it's cheap to leave running)
```bash
cd terraform/media-engine && terraform destroy
```

---

## ⚙️ CI/CD Pipeline (GitHub Actions)

| Stage | Trigger | What it does |
|-------|---------|--------------|
| **Validate** | Every push | `terraform fmt -check`, `terraform validate`, syntax checks |
| **Security** | Every push | TFLint + Checkov scanning, SARIF upload to GitHub Security |
| **Build** | Push to `src/`, `ecs/` | Build + push the FFmpeg encoder image to ECR |
| **Plan** | Pull requests | `terraform plan`, optional cost estimate, posted as a PR comment |
| **Deploy** | Merge to `main` | Apply infrastructure, update Lambda/task definition, post-deploy checks |

### Required GitHub Secrets
```
AWS_ROLE_ARN        # AWS OIDC role assumed by the pipeline
INFRACOST_API_KEY   # Optional — enables cost diffing
```

Authentication uses GitHub OIDC federation, so no long-lived AWS keys are stored in the repo.

---

## 💰 Cost

**This stack costs almost nothing at rest, and stays cheap even when you use it.** Encoding runs on Fargate Spot and bills only for the seconds a task is actually running; with no video being processed, idle cost is effectively **$0** beyond a few cents of S3 storage. There is no per-minute encoding charge and no always-on control plane.

Encoding a short demo clip across three profiles costs **a few cents** of Spot compute. Even regular test usage keeps the whole stack comfortably under **~$40–50/month**, and a true idle deployment is near-$0.

| Component | Idle | Light/demo use | Notes |
|-----------|------|----------------|-------|
| Fargate Spot (FFmpeg) | $0 | a few cents per clip | ~70% cheaper than on-demand; billed per second |
| CloudFront | $0 | ~$0 | Free tier covers 1 TB egress + 10M requests/mo (confirm on AWS free-tier page) |
| S3 Storage | a few cents | a few cents | Intelligent-Tiering + Glacier after 30 days |
| Lambda / Step Functions | $0 | ~$0 | Pay-per-execution |
| ECR image storage | ~$0.10 | ~$0.10 | One small encoder image |
| Misc (alarms, SNS) | ~$1–2 | ~$1–2 | — |
| **Total** | **~$0** | **a few dollars; < $50/mo even with regular testing** | Scales with compute time, not output minutes |

**Cost levers built in:**
- FFmpeg on **Fargate Spot** — pay only for encode time, ~70% off on-demand
- 4K is an **optional** profile (off by default) — it's the most compute-heavy rendition
- CloudFront **free-tier** egress covers all realistic demo traffic
- S3 Intelligent-Tiering + Glacier transition after 30 days
- H.265/HEVC encoding (~30% smaller output → lower storage + CDN egress)

> When would MediaConvert be the better call? At sustained high volume (thousands of output minutes/month) where its managed reliability, reserved-slot discounts, and broadcast features outweigh the per-minute cost. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## 📁 Project Structure

```
media-engine/
├── .github/
│   └── workflows/
│       ├── terraform-validate.yml
│       ├── terraform-plan.yml
│       ├── terraform-deploy.yml
│       └── image-build.yml
├── terraform/
│   └── media-engine/
│       ├── main.tf               # All infrastructure
│       ├── ecs.tf                # ECR + Fargate task definitions + cluster
│       ├── terraform.tfvars      # Variables
│       └── outputs.tf            # Outputs
├── src/
│   ├── lambda-validator.py       # Input validation + starts Step Functions
│   ├── lambda-callback.py        # Aggregates rendition results / notifies
│   └── requirements.txt
├── ecs/
│   ├── Dockerfile                # FFmpeg encoder container
│   ├── entrypoint.sh             # Pulls input from S3, encodes, pushes output
│   └── encode.sh                 # FFmpeg bitrate-ladder commands per profile
├── docs/
│   ├── ARCHITECTURE.md           # incl. FFmpeg-vs-MediaConvert decision + threshold
│   ├── DEPLOYMENT.md
│   └── TROUBLESHOOTING.md
├── scripts/
│   ├── build-and-push.sh         # Build + push encoder image to ECR
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

**Encode** — Step Functions launches one **Fargate (Spot) task per rendition** in parallel. Each task runs the FFmpeg encoder container, which pulls the source from S3, encodes to its profile (480p / 720p / 1080p, plus optional 2160p), generates thumbnails, and writes the result back to S3. Step Functions handles Spot-interruption retries.

**Distribute** — Outputs land in S3, transition to Glacier after 30 days, and are served globally through CloudFront with Origin Shield.

**Monitor** — CloudWatch captures task logs and metrics; SNS sends completion and failure notifications.

---

## 🧪 Testing & Validation

```bash
# Upload a test video
INPUT_BUCKET=$(terraform output -raw input_bucket)
aws s3 cp sample-video.mp4 s3://$INPUT_BUCKET/uploads/test.mp4

# Watch encoding tasks
CLUSTER=$(terraform output -raw ecs_cluster)
aws ecs list-tasks --cluster $CLUSTER --desired-status RUNNING
aws logs tail /ecs/media-engine-encoder --follow

# Inspect outputs
OUTPUT_BUCKET=$(terraform output -raw output_bucket)
aws s3 ls s3://$OUTPUT_BUCKET/ --recursive

# Invoke the validator directly
aws lambda invoke \
  --function-name media-engine-validator \
  --payload '{"bucket":"...","key":"test.mp4"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json

# Confirm a CloudFront cache hit
CDN=$(terraform output -raw cloudfront_domain)
curl -I https://$CDN/video-name/720p.mp4 | grep -i x-cache
```

---

## 🔐 Security

**Infrastructure**
- Private subnets for Fargate encoding tasks (VPC isolation)
- S3 encryption at rest (AES-256)
- CloudFront HTTPS with TLS 1.2+
- Least-privilege IAM, scoped per service / per task role
- No static credentials — GitHub OIDC federation only

**Code & pipeline**
- TFLint + Checkov on every push
- Container image + Python dependency scanning
- SARIF reports surfaced in GitHub Security

---

## 🧠 What This Project Demonstrates

- **Serverless + container orchestration** — event-driven processing across S3, EventBridge, Lambda, Step Functions, ECS Fargate, and CloudFront
- **Hands-on encoding** — FFmpeg bitrate ladders, codec/keyframe configuration, and HEVC, rather than calling a managed API as a black box
- **Resilience** — Spot-interruption handling and Step Functions retries on interruptible compute
- **Infrastructure as code** — Terraform with remote state, locking, ECR, and task definitions
- **CI/CD** — multi-stage GitHub Actions pipeline with OIDC auth, image build/push, security scanning
- **Cost-aware design** — a usage-driven, near-zero-idle architecture, plus a documented, defensible trade-off (FFmpeg-on-Fargate vs MediaConvert) and the exact volume threshold where the decision flips

---

## 🚀 Roadmap

- [ ] Optional MediaConvert encoding path (managed alternative for high-volume use)
- [ ] Live streaming support
- [ ] AI-assisted quality analysis
- [ ] Multi-region output replication
- [ ] Per-title / QVBR encoding for further bitrate savings
- [ ] DRM integration

---

## 📄 License

MIT License — see [LICENSE](LICENSE)

---

## 🎯 What I'm Looking For

I'm actively seeking opportunities as a **Solutions Engineer**, **Cloud Engineer**, **DevOps Engineer**, or **Junior Solutions Architect** where I can:
- Design and implement scalable cloud solutions
- Work directly with customers to solve technical problems and drive outcomes
- Apply AWS Well-Architected principles in real workloads
- Optimize cloud cost and performance

<div align="center">

<hr>

**Based in Calgary, AB | Open to relocation within Canada**

<hr>

## 📞 Let's Connect

[![Email](https://img.shields.io/badge/Email-EA4335?style=for-the-badge&logo=gmail&logoColor=white)](mailto:riyazbhattarai07@gmail.com)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/riyaz-bhattarai-836ab6323/)
[![Portfolio](https://img.shields.io/badge/Portfolio-000000?style=for-the-badge&logo=vercel&logoColor=white)](https://portfolio-ajpn.vercel.app/)
[![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/riyazbhattarai07)

</div>
