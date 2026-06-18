provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = var.project_name
      Env       = var.environment
      ManagedBy = "terraform"
    }
  }
}
