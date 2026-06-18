"""
lambda-validator.py
-------------------
Triggered by EventBridge when a new object lands in the input S3 bucket
(prefix: uploads/). Validates the object is a supported video format, then
starts a Step Functions execution to encode it into all configured renditions.

Environment variables (injected by Terraform):
  STATE_MACHINE_ARN  – ARN of the Step Functions encoding state machine
  INPUT_BUCKET       – S3 bucket name for raw uploads
  SUPPORTED_FORMATS  – Comma-separated list of allowed extensions (default: mp4,mov,avi,mkv,webm,mxf)
  MAX_FILE_SIZE_GB   – Maximum accepted file size in GB (default: 50)
"""
from __future__ import annotations

import json
import logging
import os
import re
import uuid
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

s3  = boto3.client("s3")
sfn = boto3.client("stepfunctions")

# ── Constants ─────────────────────────────────────────────────────────────────
STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
INPUT_BUCKET      = os.environ["INPUT_BUCKET"]

SUPPORTED_FORMATS: frozenset[str] = frozenset(
    ext.strip().lstrip(".")
    for ext in os.environ.get("SUPPORTED_FORMATS", "mp4,mov,avi,mkv,webm,mxf").split(",")
)
MAX_FILE_SIZE_BYTES = int(
    float(os.environ.get("MAX_FILE_SIZE_GB", "50")) * 1024 ** 3
)

# Encoding profiles in priority order; Step Functions will fan them out in parallel
DEFAULT_PROFILES = ["360p", "720p", "1080p", "2160p"]


# ── Helpers ───────────────────────────────────────────────────────────────────
def _extract_s3_event(event: dict) -> tuple[str, str]:
    """Extract bucket + key from either EventBridge or direct S3 event shapes."""
    # EventBridge S3 notification shape
    if "detail" in event and "bucket" in event.get("detail", {}):
        detail = event["detail"]
        bucket = detail["bucket"]["name"]
        key    = detail["object"]["key"]
        return bucket, key

    # Native S3 test event shape
    if "Records" in event:
        rec    = event["Records"][0]["s3"]
        bucket = rec["bucket"]["name"]
        key    = rec["object"]["key"]
        return bucket, key

    raise ValueError(f"Unrecognised event shape: {list(event.keys())}")


def _validate_object(bucket: str, key: str) -> dict[str, Any]:
    """
    Perform validation checks against the S3 object.
    Returns a dict of metadata on success; raises ValueError on failure.
    """
    # 1. Check file extension
    extension = key.rsplit(".", 1)[-1].lower() if "." in key else ""
    if extension not in SUPPORTED_FORMATS:
        raise ValueError(
            f"Unsupported format '{extension}'. Allowed: {sorted(SUPPORTED_FORMATS)}"
        )

    # 2. Head the object to confirm it exists and get its size
    try:
        head = s3.head_object(Bucket=bucket, Key=key)
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        raise ValueError(f"Cannot access s3://{bucket}/{key}: {code}") from exc

    size_bytes = head["ContentLength"]
    if size_bytes == 0:
        raise ValueError("Object is empty (0 bytes).")
    if size_bytes > MAX_FILE_SIZE_BYTES:
        raise ValueError(
            f"File too large: {size_bytes / 1024**3:.1f} GiB exceeds "
            f"{MAX_FILE_SIZE_BYTES / 1024**3:.0f} GiB limit."
        )

    # 3. Sanitize key – block path traversal
    if re.search(r"(\.\./|//)", key):
        raise ValueError(f"Suspicious path characters in key: {key!r}")

    return {
        "size_bytes": size_bytes,
        "content_type": head.get("ContentType", "application/octet-stream"),
        "etag": head["ETag"].strip('"'),
        "last_modified": head["LastModified"].isoformat(),
        "extension": extension,
    }


def _start_execution(bucket: str, key: str, metadata: dict) -> dict:
    """Start a Step Functions execution and return the response."""
    job_id   = str(uuid.uuid4())
    basename = key.rsplit("/", 1)[-1].rsplit(".", 1)[0]  # filename without extension

    payload = {
        "job_id":       job_id,
        "input_bucket": bucket,
        "input_key":    key,
        "output_prefix": f"encoded/{basename}/{job_id}",
        "profiles":     DEFAULT_PROFILES,
        "submitted_at": datetime.now(timezone.utc).isoformat(),
        "metadata":     metadata,
    }

    logger.info("Starting execution | job_id=%s key=%s", job_id, key)

    response = sfn.start_execution(
        stateMachineArn=STATE_MACHINE_ARN,
        name=f"{job_id[:8]}-{re.sub(r'[^a-zA-Z0-9_-]', '-', basename)[:64]}",
        input=json.dumps(payload),
    )

    return {
        "job_id":        job_id,
        "execution_arn": response["executionArn"],
        "started_at":    response["startDate"].isoformat(),
    }


# ── Handler ───────────────────────────────────────────────────────────────────
def handler(event: dict, context: Any) -> dict:
    """Lambda entry point."""
    logger.debug("Received event: %s", json.dumps(event))

    try:
        bucket, key = _extract_s3_event(event)
    except (ValueError, KeyError) as exc:
        logger.error("Failed to parse event: %s", exc)
        return {"statusCode": 400, "error": str(exc)}

    # Skip folders and zero-byte marker objects
    if key.endswith("/"):
        logger.info("Skipping folder marker: %s", key)
        return {"statusCode": 200, "skipped": True, "reason": "folder marker"}

    try:
        metadata = _validate_object(bucket, key)
    except ValueError as exc:
        logger.warning("Validation failed for %s: %s", key, exc)
        return {"statusCode": 422, "error": str(exc), "key": key}

    result = _start_execution(bucket, key, metadata)

    logger.info(
        "Execution started | job_id=%s execution_arn=%s",
        result["job_id"],
        result["execution_arn"],
    )
    return {"statusCode": 200, **result}
