# =============================================================================
# Outputs  – ARNs, URLs, and names that downstream systems / scripts need
# =============================================================================

# ── ECR ───────────────────────────────────────────────────────────────────────
output "ecr_repository_url" {
  description = "ECR repository URL used to tag and push encoder images."
  value       = aws_ecr_repository.encoder.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN."
  value       = aws_ecr_repository.encoder.arn
}

# ── ECS ───────────────────────────────────────────────────────────────────────
output "ecs_cluster_arn" {
  description = "ECS cluster ARN where encoder tasks are launched."
  value       = aws_ecs_cluster.encoder.arn
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.encoder.name
}

output "ecs_task_definition_arn" {
  description = "Latest active revision ARN of the encoder task definition."
  value       = aws_ecs_task_definition.encoder.arn
}

output "ecs_task_role_arn" {
  description = "IAM role ARN assumed by running encoder tasks."
  value       = aws_iam_role.ecs_task.arn
}

output "ecs_execution_role_arn" {
  description = "IAM role ARN used by ECS to pull images and write logs."
  value       = aws_iam_role.ecs_exec.arn
}

# ── Networking ────────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs used to launch Fargate tasks."
  value       = aws_subnet.public[*].id
}

output "encoder_security_group_id" {
  description = "Security group ID attached to encoder Fargate tasks."
  value       = aws_security_group.encoder.id
}

# ── S3 ────────────────────────────────────────────────────────────────────────
output "input_bucket_name" {
  description = "S3 bucket where raw video uploads are placed."
  value       = aws_s3_bucket.input.bucket
}

output "input_bucket_arn" {
  description = "S3 input bucket ARN."
  value       = aws_s3_bucket.input.arn
}

output "output_bucket_name" {
  description = "S3 bucket where encoded renditions are written."
  value       = aws_s3_bucket.output.bucket
}

output "output_bucket_arn" {
  description = "S3 output bucket ARN."
  value       = aws_s3_bucket.output.arn
}

# ── CloudFront ────────────────────────────────────────────────────────────────
output "cloudfront_domain" {
  description = "CloudFront distribution domain for serving encoded media."
  value       = aws_cloudfront_distribution.output.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (needed for cache invalidations)."
  value       = aws_cloudfront_distribution.output.id
}

# ── Step Functions ────────────────────────────────────────────────────────────
output "state_machine_arn" {
  description = "ARN of the Step Functions state machine that orchestrates encoding."
  value       = aws_sfn_state_machine.encoder.arn
}

output "state_machine_name" {
  description = "Name of the Step Functions state machine."
  value       = aws_sfn_state_machine.encoder.name
}

# ── Lambda ────────────────────────────────────────────────────────────────────
output "lambda_validator_arn" {
  description = "ARN of the validator Lambda function."
  value       = aws_lambda_function.validator.arn
}

output "lambda_callback_arn" {
  description = "ARN of the callback Lambda function."
  value       = aws_lambda_function.callback.arn
}

# ── Observability ─────────────────────────────────────────────────────────────
output "encoder_log_group" {
  description = "CloudWatch log group for encoder ECS tasks."
  value       = aws_cloudwatch_log_group.encoder.name
}
