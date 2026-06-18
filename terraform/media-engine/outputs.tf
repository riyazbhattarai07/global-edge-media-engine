output "input_bucket" {
  value = aws_s3_bucket.input.id
}

output "output_bucket" {
  value = aws_s3_bucket.output.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.encoder.repository_url
}

output "ecs_cluster" {
  value = aws_ecs_cluster.main.name
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.main.domain_name
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
