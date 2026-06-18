variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "media-engine"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "use_fargate_spot" {
  type    = bool
  default = true
}

variable "max_concurrent_tasks" {
  type    = number
  default = 10
}
