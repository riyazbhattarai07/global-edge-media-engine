"""
Callback Lambda
---------------
Invoked by Step Functions after all renditions finish.
"""
import json
import boto3
import os

sns = boto3.client('sns')

def handler(event, context):
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    message = json.dumps({
        'status': 'completed',
        'results': event.get('results', []),
    })
    if topic_arn:
        sns.publish(TopicArn=topic_arn, Message=message, Subject='Media encoding complete')
    return {'status': 'ok'}
