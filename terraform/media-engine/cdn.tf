# ---------------------------------------------------------------------------
# CloudFront distribution serving the private output bucket via Origin Access
# Control, with Origin Shield enabled for a higher cache hit ratio.
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "output" {
  name                              = "${local.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  comment             = "${local.name} media delivery"
  default_root_object = ""
  price_class         = "PriceClass_100" # NA + EU edge locations (cheapest)

  origin {
    domain_name              = aws_s3_bucket.output.bucket_regional_domain_name
    origin_id                = "output-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.output.id

    origin_shield {
      enabled              = true
      origin_shield_region = var.aws_region
    }
  }

  default_cache_behavior {
    target_origin_id       = "output-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 604800
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}

# Allow CloudFront (this distribution only) to read the output bucket.
resource "aws_s3_bucket_policy" "output_cloudfront" {
  bucket = aws_s3_bucket.output.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = ["s3:GetObject"]
      Resource  = "${aws_s3_bucket.output.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.main.arn }
      }
    }]
  })
}
