terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Configure via -backend-config flags or environment variables
    # bucket = "your-tfstate-bucket"
    # key    = "media-engine/terraform.tfstate"
    # region = "us-east-1"
  }
}
