# CloudWatch alarms on encoder failures + a simple dashboard.

resource "aws_cloudwatch_metric_alarm" "sfn_failures" {
  alarm_name          = "${local.name}-pipeline-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Media pipeline executions failing"
  treat_missing_data  = "notBreaching"
  dimensions          = { StateMachineArn = aws_sfn_state_machine.pipeline.arn }
  alarm_actions       = [aws_sns_topic.notifications.arn]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title   = "Pipeline executions"
          region  = var.aws_region
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", aws_sfn_state_machine.pipeline.arn],
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", aws_sfn_state_machine.pipeline.arn],
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", aws_sfn_state_machine.pipeline.arn]
          ]
          view = "timeSeries", stat = "Sum", period = 300
        }
      },
      {
        type = "log", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title  = "Encoder logs"
          region = var.aws_region
          query  = "SOURCE '${aws_cloudwatch_log_group.encoder.name}' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          view   = "table"
        }
      }
    ]
  })
}
