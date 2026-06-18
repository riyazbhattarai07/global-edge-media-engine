name: Deploy

on:
  push:
    branches: ["main"]

permissions:
  contents: read
  id-token: write

concurrency:
  group: deploy-media-engine
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    defaults:
      run:
        working-directory: terraform/media-engine
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.7.5"

      - name: Init
        run: terraform init -backend-config="bucket=${{ secrets.TF_STATE_BUCKET }}"

      - name: Apply
        run: terraform apply -auto-approve -input=false

      - name: Smoke checks
        run: |
          terraform output -json > outputs.json
          cat outputs.json
          aws s3 ls --recursive
          aws ecr describe-repositories --query 'repositories[].repositoryName' --output table
