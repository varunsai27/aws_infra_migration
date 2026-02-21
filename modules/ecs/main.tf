# ─────────────────────────────────────────────────────────────────────────────
# MODULE: ecs
# Provisions: ECS cluster, CloudWatch log groups, task definitions (API +
#             Worker), Fargate services, and autoscaling policies
#
# Autoscaling:
#   API     → scales on CPU utilisation (target tracking at 60%)
#   Worker  → scales on SQS queue depth (step scaling)
# ─────────────────────────────────────────────────────────────────────────────

# ── Cluster ───────────────────────────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.name_prefix}-cluster" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.name_prefix}/api"
  retention_in_days = 30
  tags              = { Name = "${var.name_prefix}-api-logs" }
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${var.name_prefix}/worker"
  retention_in_days = 30
  tags              = { Name = "${var.name_prefix}-worker-logs" }
}

# ── API Task Definition ───────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name_prefix}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.api_cpu
  memory                   = var.api_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.api_task_role_arn

  container_definitions = jsonencode([{
    name      = "api"
    image     = var.api_image
    essential = true

    portMappings = [{
      containerPort = 8000
      hostPort      = 8000
      protocol      = "tcp"
    }]

    environment = [
      { name = "SQS_QUEUE_URL", value = var.sqs_queue_url },
      { name = "DB_HOST",       value = var.db_host },
      { name = "DB_NAME",       value = var.db_name },
      { name = "DB_USER",       value = var.db_username },
      { name = "S3_BUCKET",     value = var.s3_bucket },
      { name = "LOG_LEVEL",     value = "INFO" }
    ]

    # NOTE: In production, use secrets block for DB_PASSWORD and API keys
    # secrets = [{ name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:..." }]
    secrets = [
      { name = "DB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.api.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "api"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = { Name = "${var.name_prefix}-api-task" }
}

# ── Worker Task Definition ────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.name_prefix}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.worker_task_role_arn

  container_definitions = jsonencode([{
    name      = "worker"
    image     = var.worker_image
    essential = true

    environment = [
      { name = "SQS_QUEUE_URL", value = var.sqs_queue_url },
      { name = "DB_HOST",       value = var.db_host },
      { name = "DB_NAME",       value = var.db_name },
      { name = "DB_USER",       value = var.db_username },
      { name = "S3_BUCKET",     value = var.s3_bucket },
      { name = "LOG_LEVEL",     value = "INFO" },
      # Workers use more memory — tune Celery concurrency accordingly
      { name = "CELERY_CONCURRENCY", value = "4" }
    ]

    secrets = [
      { name = "DB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.worker.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "worker"
      }
    }
  }])

  tags = { Name = "${var.name_prefix}-worker-task" }
}

# ── SSM Parameter for DB password (demo shortcut — use Secrets Manager in prod) ──
data "aws_region" "current" {}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.name_prefix}/db/password"
  type  = "SecureString"
  value = var.db_password

  tags = { Name = "${var.name_prefix}-db-password" }
}

# Grant execution role access to SSM parameter
resource "aws_iam_role_policy" "ecs_execution_ssm" {
  name = "${var.name_prefix}-ecs-execution-ssm"
  role = split("/", var.execution_role_arn)[1]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters", "ssm:GetParameter"]
      Resource = aws_ssm_parameter.db_password.arn
    }]
  })
}

# ── API ECS Service ───────────────────────────────────────────────────────────
resource "aws_ecs_service" "api" {
  name            = "${var.name_prefix}-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_min_capacity
  launch_type     = "FARGATE"

  # Rolling deploy — new tasks must be healthy before old tasks are stopped
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true # Automatically rollback if deploy fails health checks
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_group_arn
    container_name   = "api"
    container_port   = 8000
  }

  # Allow Terraform to manage desired_count alongside autoscaling
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = { Name = "${var.name_prefix}-api-service" }
}

# ── Worker ECS Service ────────────────────────────────────────────────────────
resource "aws_ecs_service" "worker" {
  name            = "${var.name_prefix}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_min_capacity
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = { Name = "${var.name_prefix}-worker-service" }
}

# ══════════════════════════════════════════════════════════════════════════════
# AUTOSCALING
# ══════════════════════════════════════════════════════════════════════════════

# ── API Autoscaling — CPU-based ───────────────────────────────────────────────
resource "aws_appautoscaling_target" "api" {
  max_capacity       = var.api_max_capacity
  min_capacity       = var.api_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "api_cpu" {
  name               = "${var.name_prefix}-api-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 60.0 # Scale out when CPU > 60%
    scale_in_cooldown  = 300  # Wait 5 min before scaling in (avoid flapping)
    scale_out_cooldown = 60   # Scale out quickly on load spikes

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# ── Worker Autoscaling — SQS queue depth ──────────────────────────────────────
# Workers scale based on how many jobs are waiting in the queue
# This directly ties compute capacity to actual work queued
resource "aws_appautoscaling_target" "worker" {
  max_capacity       = var.worker_max_capacity
  min_capacity       = var.worker_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "worker_scale_out" {
  name               = "${var.name_prefix}-worker-scale-out"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker.service_namespace

  step_scaling_policy_configuration {
    adjustment_type          = "ChangeInCapacity"
    cooldown                 = 120
    metric_aggregation_type  = "Maximum"

    # Queue depth 100–500: add 1 worker
    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 400
      scaling_adjustment          = 1
    }

    # Queue depth 500–2000: add 3 workers
    step_adjustment {
      metric_interval_lower_bound = 400
      metric_interval_upper_bound = 1500
      scaling_adjustment          = 3
    }

    # Queue depth > 2000: add 5 workers (large client spike)
    step_adjustment {
      metric_interval_lower_bound = 1500
      scaling_adjustment          = 5
    }
  }
}

resource "aws_appautoscaling_policy" "worker_scale_in" {
  name               = "${var.name_prefix}-worker-scale-in"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker.service_namespace

  step_scaling_policy_configuration {
    adjustment_type          = "ChangeInCapacity"
    cooldown                 = 300 # Wait longer before scaling in
    metric_aggregation_type  = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

# ── CloudWatch Alarms to trigger worker scaling ───────────────────────────────
resource "aws_cloudwatch_metric_alarm" "worker_scale_out_alarm" {
  alarm_name          = "${var.name_prefix}-worker-queue-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 100
  alarm_description   = "Trigger worker scale-out when queue depth exceeds 100"

  dimensions = {
    QueueName = var.sqs_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.worker_scale_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "worker_scale_in_alarm" {
  alarm_name          = "${var.name_prefix}-worker-queue-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3 # Queue must be empty for 3 consecutive periods
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 10
  alarm_description   = "Trigger worker scale-in when queue depth drops below 10"

  dimensions = {
    QueueName = var.sqs_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.worker_scale_in.arn]
}
