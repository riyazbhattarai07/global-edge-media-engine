name: Security Scan

on:
  push:
    branches: ["**"]
  pull_request:

permissions:
  contents: read
  security-events: write

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: TFLint
        uses: terraform-linters/setup-tflint@v4
      - run: tflint --recursive terraform/

      - name: Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: terraform/media-engine
          framework: terraform
          output_format: sarif
          output_file_path: results.sarif
          soft_fail: true

      - name: Upload SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: results.sarif

      - name: Container scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: 'ecs/'
          format: 'sarif'
          output: 'trivy-results.sarif'

      - name: Upload container SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-results.sarif
