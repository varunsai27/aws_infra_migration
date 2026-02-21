# ─────────────────────────────────────────────────────────────────────────────
# MODULE: iam
# Provisions: ECS execution role, API task role, Worker task role
# All roles follow least-privilege — scoped to only what each service needs
# ─────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ── ECS Execution Role ────────────────────────────────────────────────────────
# Used by ECS agent to pull images from ECR and write logs to CloudWatch
resource "aws_iam_role" "ecs_execution" {
  name               = "${var.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── API Task Role ─────────────────────────────────────────────────────────────
# Used by the running API container — send to SQS, read S3, get secrets
resource "aws_iam_role" "api_task" {
  name               = "${var.name_prefix}-api-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

data "aws_iam_policy_document" "api_task_policy" {
  # Send jobs to SQS
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
    resources = [var.sqs_queue_arn]
  }

  # Read application files from S3
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = concat(var.s3_bucket_arns, [for arn in var.s3_bucket_arns : "${arn}/*"])
  }

  # CloudWatch logs
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "api_task" {
  name   = "${var.name_prefix}-api-task-policy"
  role   = aws_iam_role.api_task.id
  policy = data.aws_iam_policy_document.api_task_policy.json
}

# ── Worker Task Role ──────────────────────────────────────────────────────────
# Used by the running Celery worker — consume from SQS, write to S3
resource "aws_iam_role" "worker_task" {
  name               = "${var.name_prefix}-worker-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

data "aws_iam_policy_document" "worker_task_policy" {
  # Consume jobs from SQS
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]
    resources = [var.sqs_queue_arn]
  }

  # Write bulk data to S3 (staging before DB import)
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = concat(var.s3_bucket_arns, [for arn in var.s3_bucket_arns : "${arn}/*"])
  }

  # CloudWatch logs
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "worker_task" {
  name   = "${var.name_prefix}-worker-task-policy"
  role   = aws_iam_role.worker_task.id
  policy = data.aws_iam_policy_document.worker_task_policy.json
}
