resource "aws_ecr_repository" "encoder" {
  name                 = "${local.name}-encoder"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = { Name = "${local.name}-encoder" }
}

resource "aws_ecs_cluster" "encoder" {
  name = "${local.name}-encoder"
  tags = { Name = "${local.name}-encoder" }
}

resource "aws_ecs_task_definition" "encoder" {
  family                   = "${local.name}-encoder"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 2048
  memory                   = 4096
  execution_role_arn       = aws_iam_role.ecs_exec.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name  = "encoder"
    image = "${aws_ecr_repository.encoder.repository_url}:latest"
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${local.name}-encoder"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}
