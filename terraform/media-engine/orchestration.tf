# Step Functions state machine for encoding orchestration
resource "aws_sfn_state_machine" "encoder" {
  name     = "${local.name}-encoder"
  role_arn = aws_iam_role.sfn.arn

  definition = jsonencode({
    Comment = "Media encoding pipeline"
    StartAt = "EncodeProfiles"
    States = {
      EncodeProfiles = {
        Type          = "Map"
        ItemsPath     = "$.profiles"
        MaxConcurrency = var.max_concurrent_tasks
        Next          = "NotifyCallback"
      }
      NotifyCallback = {
        Type     = "Task"
        Resource = aws_lambda_function.callback.arn
        End      = true
      }
    }
  })
}
