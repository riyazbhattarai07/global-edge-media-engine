# FFmpeg encoder container. Uses a static FFmpeg build + AWS CLI for S3 I/O.
FROM public.ecr.aws/docker/library/debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    awscli \
    jq \
    curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY entrypoint.sh encode.sh /app/
RUN chmod +x /app/entrypoint.sh /app/encode.sh

ENTRYPOINT ["/app/entrypoint.sh"]
