"""
Callback Lambda
---------------
Invoked by Step Functions after all renditions finish. Summarises the result
and publishes a notification to SNS.
"""
import json
import os

import boto3

sns = boto3.client("sns")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")


def lambda_handler(event, context):
    status = event.get("status", "UNKNOWN")
    key = event.get("key", "unknown")
    renditions = event.get("renditions", [])

    summary = {
        "status": status,
        "source_key": key,
        "rendition_count": len(renditions) if isinstance(renditions, list) else 0,
    }
    print(json.dumps(summary))

    if SNS_TOPIC_ARN:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[media-engine] {status}: {key}"[:100],
            Message=json.dumps(summary, indent=2),
        )
    return {"statusCode": 200, **summary}
