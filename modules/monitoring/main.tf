# ─────────────────────────────────────────────────────────────────────────────
# MODULE: monitoring
# Provisions: SNS alert topic, CloudWatch alarms for all key metrics
# Covers: ECS CPU/memory, SQS depth, RDS connections, ALB error rate
# ─────────────────────────────────────────────────────────────────────────────

# ── SNS Topic for alerts ──────────────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
  tags = { Name = "${var.name_prefix}-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── ECS API — CPU High ────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "api_cpu_high" {
  alarm_name          = "${var.name_prefix}-api-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "API CPU > 80% — check for traffic spike or inefficient query"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.api_service_name
  }
}

# ── ECS Worker — CPU High ─────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "worker_cpu_high" {
  alarm_name          = "${var.name_prefix}-worker-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Worker CPU > 90% — worker tasks may be under-provisioned"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.worker_service_name
  }
}

# ── SQS — Queue Depth Critical ────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "sqs_depth_critical" {
  alarm_name          = "${var.name_prefix}-sqs-depth-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 2000
  alarm_description   = "SQS queue depth > 2000 — workers not keeping up with load"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { QueueName = var.sqs_queue_name }
}

# ── SQS — Oldest Message Age (jobs stuck) ─────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "sqs_message_age" {
  alarm_name          = "${var.name_prefix}-sqs-message-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 900 # 15 minutes
  alarm_description   = "Oldest SQS message > 15 min — jobs may be failing or workers are down"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { QueueName = var.sqs_queue_name }
}

# ── SQS — DLQ has messages (job failures) ─────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "sqs_dlq_messages" {
  alarm_name          = "${var.name_prefix}-sqs-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "DLQ has messages — jobs are failing after max retries. Investigate immediately."
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { QueueName = "${var.sqs_queue_name}-dlq" }
}

# ── RDS — DB Connection Count ─────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "${var.name_prefix}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80 # db.t3.medium max_connections ~170; alert at ~80
  alarm_description   = "RDS connection count high — consider deploying RDS Proxy"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { DBInstanceIdentifier = var.rds_identifier }
}

# ── RDS — Low Free Storage ────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${var.name_prefix}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120 # 5 GB in bytes
  alarm_description   = "RDS free storage < 5 GB — increase allocated storage"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { DBInstanceIdentifier = var.rds_identifier }
}

# ── ALB — 5xx Error Rate ──────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_5xx_high" {
  alarm_name          = "${var.name_prefix}-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB 5xx count > 10/min — API is returning errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = { LoadBalancer = var.alb_arn_suffix }
}

# ── CloudWatch Dashboard ──────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-ops"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 8, height = 6,
        properties = {
          title  = "ECS API CPU Utilization"
          metrics = [["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.api_service_name]]
          period = 60, stat = "Average", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 8, y = 0, width = 8, height = 6,
        properties = {
          title  = "SQS Queue Depth"
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.sqs_queue_name]]
          period = 60, stat = "Maximum", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 16, y = 0, width = 8, height = 6,
        properties = {
          title  = "RDS DB Connections"
          metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_identifier]]
          period = 60, stat = "Average", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 8, height = 6,
        properties = {
          title  = "ALB Request Count & 5xx Errors"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix]
          ]
          period = 60, stat = "Sum", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 8, y = 6, width = 8, height = 6,
        properties = {
          title  = "Worker ECS CPU Utilization"
          metrics = [["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.worker_service_name]]
          period = 60, stat = "Average", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 16, y = 6, width = 8, height = 6,
        properties = {
          title  = "SQS Dead-Letter Queue"
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${var.sqs_queue_name}-dlq"]]
          period = 60, stat = "Sum", view = "timeSeries"
        }
      }
    ]
  })
}
