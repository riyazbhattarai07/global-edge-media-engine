"""
Validator Lambda
----------------
Triggered by EventBridge on S3 ObjectCreated (input bucket, uploads/ prefix).
Performs lightweight validation, then starts the Step Functions pipeline with
the list of renditions to produce.

Full media inspection (codec/resolution probing) is intentionally left as a
TODO — for a portfolio build, an extension-based check keeps cold starts cheap;
swap in a probe (e.g. an ffprobe sidecar task) if you need stricter validation.
"""
import json
import os

import boto3

sfn = boto3.client("stepfunctions")

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
PROFILES = json.loads(os.environ.get("PROFILES", '["480p","720p","1080p"]'))
ALLOWED_EXT = {".mp4", ".mov", ".mkv", ".webm", ".m4v"}


def lambda_handler(event, context):
    detail = event.get("detail", {})
    bucket = detail.get("bucket", {}).get("name")
    key = detail.get("object", {}).get("key")
    print(json.dumps({"bucket": bucket, "key": key}))

    if not bucket or not key:
        return {"statusCode": 400, "error": "missing bucket/key in event"}

    ext = os.path.splitext(key)[1].lower()
    if ext not in ALLOWED_EXT:
        return {"statusCode": 415, "error": f"unsupported extension '{ext}'", "key": key}

    execution = sfn.start_execution(
        stateMachineArn=STATE_MACHINE_ARN,
        input=json.dumps({"bucket": bucket, "key": key, "profiles": PROFILES}),
    )
    print(f"started execution {execution['executionArn']}")
    return {
        "statusCode": 200,
        "executionArn": execution["executionArn"],
        "profiles": PROFILES,
    }
