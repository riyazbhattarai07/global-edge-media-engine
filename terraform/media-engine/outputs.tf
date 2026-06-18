output "cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.output.domain_name
}

output "input_bucket" {
  description = "S3 input bucket name"
  value       = aws_s3_bucket.input.bucket
}

output "output_bucket" {
  description = "S3 output bucket name"
  value       = aws_s3_bucket.output.bucket
}

output "ecr_repository_url" {
  description = "ECR repository URL for encoder image"
  value       = aws_ecr_repository.encoder.repository_url
}
