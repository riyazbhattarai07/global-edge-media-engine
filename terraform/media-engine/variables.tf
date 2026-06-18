# =============================================================================
# Input Variables
# =============================================================================

# ── Deployment Context ────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region to deploy all resources into."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment. Controls naming, tagging, and cost-saving options."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Short project identifier. Used as a prefix for all resource names."
  type        = string
  default     = "media-engine"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with hyphens, 3-21 chars."
  }
}

variable "owner" {
  description = "Team or person responsible for these resources (used in cost-allocation tags)."
  type        = string
  default     = "platform"
}

# ── Networking ────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

# ── ECS / Fargate ─────────────────────────────────────────────────────────────
variable "use_fargate_spot" {
  description = "Use Fargate Spot for encoder tasks. Cuts compute cost ~70% at the risk of interruption (retried automatically)."
  type        = bool
  default     = true
}

variable "encoder_task_cpu" {
  description = "vCPU units for the encoder Fargate task (1 vCPU = 1024 units)."
  type        = number
  default     = 4096   # 4 vCPU – enough for parallel H.264/H.265 streams

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.encoder_task_cpu)
    error_message = "encoder_task_cpu must be a valid Fargate CPU value."
  }
}

variable "encoder_task_memory" {
  description = "Memory in MiB for the encoder Fargate task."
  type        = number
  default     = 8192   # 8 GiB
}

variable "encoder_ephemeral_storage_gb" {
  description = "Ephemeral storage in GiB attached to each encoder task. Set >= 2× the largest expected input file."
  type        = number
  default     = 100

  validation {
    condition     = var.encoder_ephemeral_storage_gb >= 21 && var.encoder_ephemeral_storage_gb <= 200
    error_message = "encoder_ephemeral_storage_gb must be between 21 and 200."
  }
}

variable "max_concurrent_tasks" {
  description = "Maximum number of concurrent ECS encoding tasks launched by the Step Functions Map state."
  type        = number
  default     = 10
}

# ── Step Functions ────────────────────────────────────────────────────────────
variable "sfn_log_level" {
  description = "Logging level for the Step Functions state machine execution logs."
  type        = string
  default     = "ERROR"

  validation {
    condition     = contains(["OFF", "ALL", "ERROR", "FATAL"], var.sfn_log_level)
    error_message = "sfn_log_level must be OFF, ALL, ERROR, or FATAL."
  }
}

# ── Storage ───────────────────────────────────────────────────────────────────
variable "input_object_ttl_days" {
  description = "Days before raw input objects in the input bucket are automatically deleted."
  type        = number
  default     = 7
}

variable "output_glacier_transition_days" {
  description = "Days before encoded output objects are transitioned to Glacier Instant Retrieval."
  type        = number
  default     = 30
}

# ── Observability ─────────────────────────────────────────────────────────────
variable "log_retention_days" {
  description = "Days to retain CloudWatch log groups."
  type        = number
  default     = 30
}

variable "alarm_notification_email" {
  description = "Email address to receive CloudWatch alarm notifications via SNS."
  type        = string
  default     = ""
}

# ── Lambda ────────────────────────────────────────────────────────────────────
variable "lambda_memory_mb" {
  description = "Memory in MB for the validator and callback Lambda functions."
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Timeout in seconds for Lambda functions."
  type        = number
  default     = 30
}
