# Deployment

## Prerequisites

- Terraform >= 1.5, AWS CLI >= 2.0, Docker
- An S3 bucket + DynamoDB table for remote state
- AWS credentials with sufficient permissions

## Quick Start

```bash
cd terraform/media-engine
terraform init
terraform plan
terraform apply
```

## Build and push encoder image

```bash
./scripts/build-and-push.sh
```

## Deploy Lambda functions

```bash
./scripts/deploy-lambdas.sh
```
