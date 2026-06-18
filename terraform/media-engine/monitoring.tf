# CloudWatch alarms on encoder failures + a simple dashboard.
resource "aws_cloudwatch_metric_alarm" "sfn_failures" {
  alarm_name          = "${local.name}-sfn-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Step Functions execution failures"
  dimensions          = { StateMachineArn = aws_sfn_state_machine.encoder.arn }
}
