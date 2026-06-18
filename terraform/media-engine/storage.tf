# S3: input (raw uploads, short TTL) and output (encoded renditions, long-lived)
resource "aws_s3_bucket" "input" {
  bucket = "${local.name}-input"
  tags   = { Name = "${local.name}-input" }
}

resource "aws_s3_bucket" "output" {
  bucket = "${local.name}-output"
  tags   = { Name = "${local.name}-output" }
}

resource "aws_s3_bucket_lifecycle_configuration" "input" {
  bucket = aws_s3_bucket.input.id

  rule {
    id     = "expire-raw"
    status = "Enabled"
    expiration { days = 7 }
  }
}
