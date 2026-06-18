"""
lambda-callback.py
------------------
Invoked by Step Functions after all encoding Map-state branches finish.
Responsibilities:
  1. Aggregate per-profile rendition results (success / failure / skipped)
  2. Compute total output size and encoding duration
  3. Write a job-completion record to DynamoDB
  4. Publish a structured SNS notification
  5. Return a final status summary to Step Functions

Environment variables (injected by Terraform):
  SNS_TOPIC_ARN      – ARN of the SNS topic for notifications
  JOBS_TABLE_NAME    – DynamoDB table name for job state
  OUTPUT_BUCKET      – S3 bucket where renditions were written
"""
from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

sns      = boto3.client("sns")
dynamodb = boto3.resource("dynamodb")
s3       = boto3.client("s3")

SNS_TOPIC_ARN   = os.environ.get("SNS_TOPIC_ARN", "")
JOBS_TABLE_NAME = os.environ.get("JOBS_TABLE_NAME", "")
OUTPUT_BUCKET   = os.environ["OUTPUT_BUCKET"]


# ── Helpers ───────────────────────────────────────────────────────────────────
def _aggregate_results(profile_results: list[dict]) -> dict:
    """
    Given the list of per-profile Step Functions branch outputs,
    return a structured summary.
    """
    succeeded, failed, skipped = [], [], []
    total_output_bytes = 0

    for result in profile_results:
        profile = result.get("profile", "unknown")
        status  = result.get("status", "unknown")

        if status == "succeeded":
            succeeded.append({
                "profile":      profile,
                "output_key":   result.get("output_key", ""),
                "size_bytes":   result.get("output_size_bytes", 0),
                "duration_s":   result.get("encoding_duration_s", 0),
                "codec":        result.get("codec", ""),
            })
            total_output_bytes += result.get("output_size_bytes", 0)
        elif status == "failed":
            failed.append({
                "profile": profile,
                "error":   result.get("error", "unknown error"),
            })
        else:
            skipped.append({"profile": profile, "reason": result.get("reason", "")})

    overall_status = (
        "succeeded"       if not failed and succeeded else
        "partial_failure" if failed and succeeded   else
        "failed"
    )

    return {
        "overall_status":      overall_status,
        "succeeded_profiles":  succeeded,
        "failed_profiles":     failed,
        "skipped_profiles":    skipped,
        "total_renditions":    len(profile_results),
        "succeeded_count":     len(succeeded),
        "failed_count":        len(failed),
        "total_output_bytes":  total_output_bytes,
        "total_output_mb":     round(total_output_bytes / 1024 ** 2, 2),
    }


def _write_dynamo(job_id: str, payload: dict) -> None:
    """Persist job completion record to DynamoDB (best-effort)."""
    if not JOBS_TABLE_NAME:
        return
    try:
        table = dynamodb.Table(JOBS_TABLE_NAME)
        table.put_item(Item={
            "job_id":       job_id,
            "completed_at": payload["completed_at"],
            **payload,
        })
        logger.info("DynamoDB record written for job %s", job_id)
    except ClientError as exc:
        logger.warning("DynamoDB write failed for %s: %s", job_id, exc)


def _publish_sns(job_id: str, payload: dict) -> None:
    """Publish structured completion notification to SNS (best-effort)."""
    if not SNS_TOPIC_ARN:
        return
    status = payload.get("overall_status", "unknown")
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[media-engine] Job {status.upper()}: {job_id[:8]}",
            Message=json.dumps(payload, indent=2),
            MessageAttributes={
                "status": {
                    "DataType":    "String",
                    "StringValue": status,
                },
                "job_id": {
                    "DataType":    "String",
                    "StringValue": job_id,
                },
            },
        )
        logger.info("SNS notification published for job %s", job_id)
    except ClientError as exc:
        logger.warning("SNS publish failed for %s: %s", job_id, exc)


# ── Handler ───────────────────────────────────────────────────────────────────
def handler(event: dict, context: Any) -> dict:
    """
    Expected event shape (from Step Functions Map state output):
    {
      "job_id":         "<uuid>",
      "input_bucket":   "<bucket>",
      "input_key":      "<s3-key>",
      "output_prefix":  "encoded/<basename>/<job_id>",
      "submitted_at":   "<iso8601>",
      "metadata":       { ... },
      "results":        [ { profile, status, output_key, ... }, ... ]
    }
    """
    logger.debug("Callback event: %s", json.dumps(event))

    job_id   = event.get("job_id", "unknown")
    results  = event.get("results", [])
    summary  = _aggregate_results(results)

    completed_at = datetime.now(timezone.utc).isoformat()

    payload = {
        "job_id":           job_id,
        "input_bucket":     event.get("input_bucket", ""),
        "input_key":        event.get("input_key", ""),
        "output_bucket":    OUTPUT_BUCKET,
        "output_prefix":    event.get("output_prefix", ""),
        "submitted_at":     event.get("submitted_at", ""),
        "completed_at":     completed_at,
        "overall_status":   summary["overall_status"],
        "succeeded_count":  summary["succeeded_count"],
        "failed_count":     summary["failed_count"],
        "total_output_mb":  summary["total_output_mb"],
        "succeeded_profiles": summary["succeeded_profiles"],
        "failed_profiles":    summary["failed_profiles"],
        "skipped_profiles":   summary["skipped_profiles"],
    }

    logger.info(
        "Job %s completed | status=%s succeeded=%d failed=%d output_mb=%.1f",
        job_id,
        summary["overall_status"],
        summary["succeeded_count"],
        summary["failed_count"],
        summary["total_output_mb"],
    )

    _write_dynamo(job_id, payload)
    _publish_sns(job_id, payload)

    return payload
