# ─────────────────────────────────────────────────────────────────────────────
# MODULE: sqs
# Provisions: Task queue + Dead-letter queue
# Workers scale on queue depth; DLQ captures failed jobs after max retries
# ─────────────────────────────────────────────────────────────────────────────

# ── Dead-Letter Queue ─────────────────────────────────────────────────────────
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-tasks-dlq"
  message_retention_seconds = 1209600 # 14 days — enough time to investigate and replay

  tags = { Name = "${var.name_prefix}-tasks-dlq" }
}

# ── Main Task Queue ───────────────────────────────────────────────────────────
resource "aws_sqs_queue" "tasks" {
  name                       = "${var.name_prefix}-tasks"
  visibility_timeout_seconds = 300  # 5 min — must exceed longest expected job duration
  message_retention_seconds  = 86400 # 24 hours
  receive_wait_time_seconds  = 20   # Long polling — reduces empty receives and cost

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3 # Job retried 3 times before moving to DLQ
  })

  tags = { Name = "${var.name_prefix}-tasks" }
}

# ── Queue Policy ──────────────────────────────────────────────────────────────
resource "aws_sqs_queue_policy" "tasks" {
  queue_url = aws_sqs_queue.tasks.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "sqs:*"
      Resource  = aws_sqs_queue.tasks.arn
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}
