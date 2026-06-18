variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "demo"
}

variable "project_name" {
  type    = string
  default = "media-engine"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "encoding_profiles" {
  description = "Renditions to produce. 2160p (4K) is optional and the most compute-heavy."
  type        = list(string)
  default     = ["480p", "720p", "1080p"]
}

variable "use_fargate_spot" {
  description = "Run encoder tasks on Fargate Spot (cheaper, interruptible)."
  type        = bool
  default     = true
}

variable "task_cpu" {
  description = "Fargate task CPU units (1024 = 1 vCPU)."
  type        = number
  default     = 2048
}

variable "task_memory" {
  description = "Fargate task memory (MiB)."
  type        = number
  default     = 4096
}

variable "storage_retention_days" {
  description = "Days before output objects transition to Glacier."
  type        = number
  default     = 30
}

variable "input_ttl_days" {
  description = "Days before raw uploads are expired from the input bucket."
  type        = number
  default     = 7
}
