"""
Validator Lambda
----------------
Triggered by EventBridge on S3 ObjectCreated (input bucket, uploads/ prefix).
"""
import json
import boto3
import os

sfn = boto3.client('stepfunctions')

def handler(event, context):
    detail = event.get('detail', {})
    bucket = detail.get('bucket', {}).get('name')
    key = detail.get('object', {}).get('key')

    if not bucket or not key:
        raise ValueError('Missing bucket or key in event')

    input_payload = json.dumps({
        'input_bucket': bucket,
        'input_key': key,
        'profiles': ['360p', '720p', '1080p', '2160p'],
    })

    response = sfn.start_execution(
        stateMachineArn=os.environ['STATE_MACHINE_ARN'],
        input=input_payload,
    )
    return {'executionArn': response['executionArn']}
