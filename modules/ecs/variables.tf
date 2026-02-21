variable "name_prefix"          { type = string }
variable "vpc_id"               { type = string }
variable "private_subnet_ids"   { type = list(string) }
variable "ecs_sg_id"            { type = string }
variable "alb_target_group_arn" { type = string }
variable "execution_role_arn"   { type = string }
variable "api_task_role_arn"    { type = string }
variable "worker_task_role_arn" { type = string }
variable "api_image"            { type = string }
variable "worker_image"         { type = string }
variable "api_cpu"              { type = number }
variable "api_memory"           { type = number }
variable "worker_cpu"           { type = number }
variable "worker_memory"        { type = number }
variable "api_min_capacity"     { type = number }
variable "api_max_capacity"     { type = number }
variable "worker_min_capacity"  { type = number }
variable "worker_max_capacity"  { type = number }
variable "sqs_queue_url"        { type = string }
variable "sqs_queue_name" {
  type    = string
  default = ""
}
variable "db_host"     { type = string }
variable "db_name"     { type = string }
variable "db_username" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "s3_bucket" { type = string }
