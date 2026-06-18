# ---------------------------------------------------------------------------
# ECS cluster + Fargate (Spot) task definition for the FFmpeg encoder.
# Step Functions launches one task per rendition (see orchestration.tf).
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = "${local.name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
  }
}

resource "aws_cloudwatch_log_group" "encoder" {
  name              = "/ecs/${local.name}-encoder"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "encoder" {
  family                   = "${local.name}-encoder"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "encoder"
      image     = "${aws_ecr_repository.encoder.repository_url}:latest"
      essential = true
      environment = [
        { name = "OUTPUT_BUCKET", value = aws_s3_bucket.output.id },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.encoder.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "encode"
        }
      }
    }
  ])
}
