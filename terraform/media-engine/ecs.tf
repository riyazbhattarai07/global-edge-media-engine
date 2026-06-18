# =============================================================================
# ECS / ECR / Fargate Infrastructure
# Creates: ECR repository, ECS Cluster (Fargate + Fargate Spot), Task Definition,
#          IAM execution + task roles, CloudWatch log group.
# =============================================================================

# -----------------------------------------------------------------------------
# ECR Repository
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "encoder" {
  name                 = "${local.name}-encoder"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, { Name = "${local.name}-encoder" })
}

resource "aws_ecr_lifecycle_policy" "encoder" {
  repository = aws_ecr_repository.encoder.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "encoder" {
  name              = "/ecs/${local.name}-encoder"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# -----------------------------------------------------------------------------
# ECS Cluster with Fargate + Fargate Spot capacity
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "encoder" {
  name = "${local.name}-encoder"

  setting {
    name  = "containerInsights"
    value = var.environment == "prod" ? "enabled" : "disabled"
  }

  tags = merge(local.common_tags, { Name = "${local.name}-encoder" })
}

resource "aws_ecs_cluster_capacity_providers" "encoder" {
  cluster_name = aws_ecs_cluster.encoder.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
    base              = 0
  }
}

# -----------------------------------------------------------------------------
# IAM – ECS Task Execution Role (pulls image, writes logs)
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_exec" {
  name               = "${local.name}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_exec_managed" {
  role       = aws_iam_role.ecs_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow pulling SSM parameters (for secrets if needed)
resource "aws_iam_role_policy" "ecs_exec_ssm" {
  name = "ssm-readonly"
  role = aws_iam_role.ecs_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameters", "ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${local.name}/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM – ECS Task Role (runtime S3, Step Functions, CloudWatch access)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task" {
  name               = "${local.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "s3-media-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadInput"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:HeadObject"]
        Resource = "${aws_s3_bucket.input.arn}/*"
      },
      {
        Sid    = "WriteOutput"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:PutObjectTagging"
        ]
        Resource = "${aws_s3_bucket.output.arn}/*"
      },
      {
        Sid      = "ListBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.input.arn, aws_s3_bucket.output.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_sfn" {
  name = "sfn-send-task-result"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:SendTaskSuccess",
          "states:SendTaskFailure",
          "states:SendTaskHeartbeat"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.encoder.arn}:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "encoder" {
  family                   = "${local.name}-encoder"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.encoder_task_cpu
  memory                   = var.encoder_task_memory
  execution_role_arn       = aws_iam_role.ecs_exec.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  # Increase ephemeral storage for large video files (20–200 GB)
  ephemeral_storage {
    size_in_gib = var.encoder_ephemeral_storage_gb
  }

  container_definitions = jsonencode([
    {
      name      = "encoder"
      image     = "${aws_ecr_repository.encoder.repository_url}:latest"
      essential = true

      environment = [
        { name = "OUTPUT_BUCKET", value = aws_s3_bucket.output.bucket },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "LOG_LEVEL", value = var.environment == "prod" ? "WARN" : "DEBUG" }
      ]

      # INPUT_BUCKET, INPUT_KEY, PROFILE, TASK_TOKEN injected at runtime by Step Functions

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.encoder.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "false"
        }
      }

      # Resource limits – prevent runaway processes
      ulimits = [
        {
          name      = "nofile"
          softLimit = 65536
          hardLimit = 65536
        }
      ]

      stopTimeout = 120  # Grace period for graceful shutdown
    }
  ])

  tags = merge(local.common_tags, { Name = "${local.name}-encoder" })
}
