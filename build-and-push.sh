# FFmpeg encoder container. Uses a static FFmpeg build + AWS CLI for S3 I/O.
FROM public.ecr.aws/docker/library/debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg ca-certificates unzip curl python3 && \
    curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscli.zip && \
    unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install && \
    rm -rf /tmp/awscli.zip /tmp/aws /var/lib/apt/lists/*

WORKDIR /work
COPY entrypoint.sh encode.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/encode.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
