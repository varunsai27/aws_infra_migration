variable "name_prefix"         { type = string }
variable "alert_email"         { type = string }
variable "sqs_queue_name"      { type = string }
variable "ecs_cluster_name"    { type = string }
variable "api_service_name"    { type = string }
variable "worker_service_name" { type = string }
variable "rds_identifier"      { type = string }
variable "alb_arn_suffix"      { type = string }
