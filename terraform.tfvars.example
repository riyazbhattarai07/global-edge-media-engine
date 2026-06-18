provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = var.project_name
      Env       = var.environment
      ManagedBy = "terraform"
      Repo      = "media-engine"
    }
  }
}

# CloudFront + ACM for the default domain live in us-east-1; this aliased
# provider is used for the distribution's cert if you later add a custom domain.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" { state = "available" }
