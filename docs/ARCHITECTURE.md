# Architecture

## Overview

The media engine is an event-driven, serverless video processing pipeline.

## Data Flow

```
Client Upload → S3 Input → EventBridge → Lambda Validator
                                              ↓
                                     Step Functions
                                              ↓
                               ECS Fargate (FFmpeg Encoder)
                                              ↓
                                         S3 Output → CloudFront
                                              ↓
                                    Lambda Callback → SNS
```

## FFmpeg vs MediaConvert Decision

For jobs under ~30 minutes of total compute, custom FFmpeg on Fargate Spot is more cost-effective. Above this threshold, AWS Elemental MediaConvert provides better per-job pricing at scale.
