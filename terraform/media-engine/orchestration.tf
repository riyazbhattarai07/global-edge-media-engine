# ---------------------------------------------------------------------------
# SNS, Lambdas (validator + callback), Step Functions pipeline, and the
# EventBridge rule that kicks the validator on each upload.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "notifications" {
  name = "${local.name}-notifications"
}

# --- Package Lambdas ---
data "archive_file" "validator" {
  type        = "zip"
  source_file = "${path.module}/../../src/lambda-validator.py"
  output_path = "${path.module}/build/validator.zip"
}

data "archive_file" "callback" {
  type        = "zip"
  source_file = "${path.module}/../../src/lambda-callback.py"
  output_path = "${path.module}/build/callback.zip"
}

resource "aws_lambda_function" "validator" {
  function_name    = "${local.name}-validator"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "lambda-validator.lambda_handler"
  timeout          = 30
  filename         = data.archive_file.validator.output_path
  source_code_hash = data.archive_file.validator.output_base64sha256

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.pipeline.arn
      PROFILES          = jsonencode(var.encoding_profiles)
      OUTPUT_BUCKET     = aws_s3_bucket.output.id
    }
  }
}

resource "aws_lambda_function" "callback" {
  function_name    = "${local.name}-callback"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "lambda-callback.lambda_handler"
  timeout          = 30
  filename         = data.archive_file.callback.output_path
  source_code_hash = data.archive_file.callback.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.notifications.arn
    }
  }
}

# --- Step Functions: validate -> Map(one Fargate task per rendition) -> notify ---
resource "aws_sfn_state_machine" "pipeline" {
  name     = "${local.name}"
  role_arn = aws_iam_role.sfn.arn

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  definition = jsonencode({
    Comment = "Media engine: parallel FFmpeg-on-Fargate encode"
    StartAt = "EncodeRenditions"
    States = {
      EncodeRenditions = {
        Type           = "Map"
        ItemsPath      = "$.profiles"
        MaxConcurrency = 0
        Parameters = {
          "profile.$" = "$$.Map.Item.Value"
          "bucket.$"  = "$.bucket"
          "key.$"     = "$.key"
        }
        Iterator = {
          StartAt = "RunEncoder"
          States = {
            RunEncoder = {
              Type     = "Task"
              Resource = "arn:aws:states:::ecs:runTask.sync"
              Parameters = {
                Cluster        = aws_ecs_cluster.main.arn
                TaskDefinition = aws_ecs_task_definition.encoder.arn
                LaunchType     = var.use_fargate_spot ? null : "FARGATE"
                CapacityProviderStrategy = var.use_fargate_spot ? [
                  { CapacityProvider = "FARGATE_SPOT", Weight = 1 }
                ] : null
                NetworkConfiguration = {
                  AwsvpcConfiguration = {
                    Subnets        = aws_subnet.public[*].id
                    SecurityGroups = [aws_security_group.encoder.id]
                    AssignPublicIp = "ENABLED"
                  }
                }
                Overrides = {
                  ContainerOverrides = [{
                    Name = "encoder"
                    Environment = [
                      { "Name" = "INPUT_BUCKET", "Value.$" = "$.bucket" },
                      { "Name" = "INPUT_KEY", "Value.$" = "$.key" },
                      { "Name" = "PROFILE", "Value.$" = "$.profile" }
                    ]
                  }]
                }
              }
              Retry = [
                {
                  ErrorEquals     = ["States.TaskFailed", "ECS.AmazonECSException"]
                  IntervalSeconds = 30
                  MaxAttempts     = 3
                  BackoffRate     = 2.0
                  Comment         = "Retry Spot interruptions / transient ECS errors"
                }
              ]
              End = true
            }
          }
        }
        Next = "Notify"
      }
      Notify = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.callback.arn
          "Payload" = {
            "status"    = "COMPLETE"
            "key.$"     = "$[0].key"
            "renditions.$" = "$"
          }
        }
        End = true
      }
    }
  })
}

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/vendedlogs/states/${local.name}"
  retention_in_days = 7
}

# --- EventBridge: S3 ObjectCreated in input/uploads -> validator Lambda ---
resource "aws_cloudwatch_event_rule" "upload" {
  name        = "${local.name}-upload"
  description = "Trigger validation when a video is uploaded"
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.input.id] }
      object = { key = [{ prefix = "uploads/" }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "upload" {
  rule      = aws_cloudwatch_event_rule.upload.name
  target_id = "validator"
  arn       = aws_lambda_function.validator.arn
}

resource "aws_lambda_permission" "upload" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.upload.arn
}
