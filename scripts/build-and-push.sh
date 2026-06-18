#!/usr/bin/env bash
# =============================================================================
# build-and-push.sh  –  Build the FFmpeg encoder image and push to Amazon ECR
#
# Works both locally (requires aws CLI + Docker) and in CI (GitHub Actions via OIDC).
#
# Usage:
#   ./scripts/build-and-push.sh [OPTIONS]
#
# Options:
#   -r, --region     AWS region          (default: us-east-1 or $AWS_REGION)
#   -e, --env        Environment suffix  (default: dev or $TF_ENV)
#   -t, --tag        Image tag           (default: git short-SHA or 'local')
#   -p, --platform   Docker platform     (default: linux/amd64)
#       --no-cache   Disable Docker layer cache
#       --push-only  Skip build, only tag+push an existing local image
#       --dry-run    Print commands without executing
#
# Prerequisites:
#   - Docker 20.10+
#   - AWS CLI v2 configured (or OIDC in CI)
#   - Terraform outputs must include ecr_repository_url
# =============================================================================
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
AWS_REGION_DEFAULT="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${TF_ENV:-dev}"
PLATFORM="linux/amd64"
NO_CACHE=""
PUSH_ONLY=false
DRY_RUN=false
IMAGE_NAME="media-engine-encoder"

# Derive git tag; fall back to 'local' if not in a git repo
if git rev-parse --short HEAD &>/dev/null; then
  DEFAULT_TAG="sha-$(git rev-parse --short HEAD)"
else
  DEFAULT_TAG="local"
fi
IMAGE_TAG="${DEFAULT_TAG}"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region)   AWS_REGION_DEFAULT="$2"; shift 2 ;;
    -e|--env)      ENVIRONMENT="$2";        shift 2 ;;
    -t|--tag)      IMAGE_TAG="$2";          shift 2 ;;
    -p|--platform) PLATFORM="$2";           shift 2 ;;
    --no-cache)    NO_CACHE="--no-cache";   shift   ;;
    --push-only)   PUSH_ONLY=true;         shift   ;;
    --dry-run)     DRY_RUN=true;           shift   ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
run() {
  echo "+ $*"
  if [[ "${DRY_RUN}" == "true" ]]; then return 0; fi
  "$@"
}

check_deps() {
  local missing=()
  for cmd in docker aws jq; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools: ${missing[*]}" >&2
    exit 1
  fi
}

# ── Resolve ECR URL ───────────────────────────────────────────────────────────
resolve_ecr_url() {
  # Try Terraform outputs first (most reliable in CI)
  if command -v terraform &>/dev/null && [[ -f "terraform/media-engine/terraform.tfstate" ]]; then
    ECR_URL=$(terraform -chdir=terraform/media-engine output -raw ecr_repository_url 2>/dev/null || true)
  fi

  # Fall back to constructing from account ID
  if [[ -z "${ECR_URL:-}" ]]; then
    ACCOUNT_ID=$(aws sts get-caller-identity \
      --query Account --output text \
      --region "${AWS_REGION_DEFAULT}")
    ECR_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION_DEFAULT}.amazonaws.com/${IMAGE_NAME}"
    echo "Resolved ECR URL from account: ${ECR_URL}"
  else
    echo "Resolved ECR URL from Terraform: ${ECR_URL}"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  echo "=== Media Engine – Build & Push ==="
  echo "  Region:      ${AWS_REGION_DEFAULT}"
  echo "  Environment: ${ENVIRONMENT}"
  echo "  Tag:         ${IMAGE_TAG}"
  echo "  Platform:    ${PLATFORM}"
  echo "  Dry run:     ${DRY_RUN}"
  echo ""

  check_deps
  resolve_ecr_url

  FULL_URI="${ECR_URL}:${IMAGE_TAG}"
  LATEST_URI="${ECR_URL}:latest"

  # ── ECR Login ──────────────────────────────────────────────────────────────
  echo "→ Authenticating with ECR..."
  run aws ecr get-login-password \
    --region "${AWS_REGION_DEFAULT}" \
    | docker login \
        --username AWS \
        --password-stdin \
        "$(echo "${ECR_URL}" | cut -d/ -f1)"

  # ── Build ──────────────────────────────────────────────────────────────────
  if [[ "${PUSH_ONLY}" == "false" ]]; then
    echo "→ Building image: ${FULL_URI}..."
    run docker build \
      --platform "${PLATFORM}" \
      ${NO_CACHE} \
      --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --build-arg VCS_REF="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')" \
      --tag "${FULL_URI}" \
      --tag "${LATEST_URI}" \
      ./ecs
  else
    echo "→ Push-only mode: tagging existing image..."
    run docker tag "${IMAGE_NAME}:latest" "${FULL_URI}"
    run docker tag "${IMAGE_NAME}:latest" "${LATEST_URI}"
  fi

  # ── Push ───────────────────────────────────────────────────────────────────
  echo "→ Pushing ${FULL_URI}..."
  run docker push "${FULL_URI}"
  echo "→ Pushing ${LATEST_URI}..."
  run docker push "${LATEST_URI}"

  # ── Summary ────────────────────────────────────────────────────────────────
  DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${FULL_URI}" 2>/dev/null || echo "(dry run)")
  echo ""
  echo "=== Push complete ==="
  echo "  URI:    ${FULL_URI}"
  echo "  Digest: ${DIGEST}"
}

main "$@"
