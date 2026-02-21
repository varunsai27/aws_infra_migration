output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "nat_gateway_elastic_ip" {
  description = "Fixed Elastic IP for outbound traffic — use this for partner IP whitelisting"
  value       = module.networking.nat_gateway_eip
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "api_service_name" {
  description = "ECS API service name"
  value       = module.ecs.api_service_name
}

output "worker_service_name" {
  description = "ECS Worker service name"
  value       = module.ecs.worker_service_name
}

output "sqs_queue_url" {
  description = "SQS task queue URL"
  value       = module.sqs.queue_url
}

output "sqs_dlq_url" {
  description = "SQS dead-letter queue URL"
  value       = module.sqs.dlq_url
}

output "db_endpoint" {
  description = "RDS primary endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "db_replica_endpoint" {
  description = "RDS read replica endpoint"
  value       = module.rds.replica_endpoint
  sensitive   = true
}

output "app_s3_bucket" {
  description = "Application S3 bucket name"
  value       = module.s3.app_bucket_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}
