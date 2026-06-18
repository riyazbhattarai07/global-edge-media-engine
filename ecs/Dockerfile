# =============================================================================
# FFmpeg Encoder Container
# Base:    Debian Bookworm Slim (small, glibc, official apt repo)
# FFmpeg:  Installed from debian-backports for a recent release with H.265 support
# AWS CLI: v2 for S3 I/O (lighter than boto3 for shell scripts)
# =============================================================================
FROM public.ecr.aws/docker/library/debian:bookworm-slim AS base

ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.title="media-engine-encoder" \
      org.opencontainers.image.description="FFmpeg encoder container for AWS Fargate"

# ── System packages ───────────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    # FFmpeg with H.264 (libx264) and H.265 (libx265) support
    ffmpeg \
    # Metadata and thumbnail extraction
    ffprobe \
    # AWS CLI dependencies
    curl \
    unzip \
    ca-certificates \
    # jq for JSON parsing in shell scripts
    jq \
    # For timing and sleep in scripts
    util-linux \
  && rm -rf /var/lib/apt/lists/*

# ── AWS CLI v2 ────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
  && unzip -q /tmp/awscliv2.zip -d /tmp \
  && /tmp/aws/install \
  && rm -rf /tmp/awscliv2.zip /tmp/aws

# ── Verify installations ──────────────────────────────────────────────────────
RUN ffmpeg -version | head -1 \
  && aws --version \
  && jq --version

# ── Application files ─────────────────────────────────────────────────────────
WORKDIR /app

COPY encode.sh      /app/encode.sh
COPY entrypoint.sh  /app/entrypoint.sh

RUN chmod +x /app/encode.sh /app/entrypoint.sh

# ── Runtime configuration ─────────────────────────────────────────────────────
# All sensitive config is injected at runtime by ECS via environment variables:
#   INPUT_BUCKET, INPUT_KEY, OUTPUT_BUCKET, PROFILE, TASK_TOKEN

# Unprivileged user for better security posture
RUN groupadd -r encoder && useradd -r -g encoder -s /sbin/nologin encoder
USER encoder

ENTRYPOINT ["/app/entrypoint.sh"]
