# ─────────────────────────────────────────────────────────────────────────────
# ROOT MODULE — wires all child modules together
# ─────────────────────────────────────────────────────────────────────────────

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── 1. Networking ─────────────────────────────────────────────────────────────
module "networking" {
  source = "./modules/networking"

  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# ── 2. IAM ────────────────────────────────────────────────────────────────────
module "iam" {
  source = "./modules/iam"

  name_prefix    = local.name_prefix
  sqs_queue_arn  = module.sqs.queue_arn
  s3_bucket_arns = [module.s3.app_bucket_arn]
}

# ── 3. S3 ─────────────────────────────────────────────────────────────────────
module "s3" {
  source      = "./modules/s3"
  name_prefix = local.name_prefix
}

# ── 4. SQS ────────────────────────────────────────────────────────────────────
module "sqs" {
  source      = "./modules/sqs"
  name_prefix = local.name_prefix
}

# ── 5. ALB ────────────────────────────────────────────────────────────────────
module "alb" {
  source = "./modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  alb_sg_id         = module.networking.alb_sg_id
}

# ── 6. RDS ────────────────────────────────────────────────────────────────────
module "rds" {
  source = "./modules/rds"

  name_prefix        = local.name_prefix
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  rds_sg_id          = module.networking.rds_sg_id
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  instance_class     = var.db_instance_class
  allocated_storage  = var.db_allocated_storage
}

# ── 7. ECS ────────────────────────────────────────────────────────────────────
module "ecs" {
  source = "./modules/ecs"

  name_prefix        = local.name_prefix
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  ecs_sg_id          = module.networking.ecs_sg_id
  alb_target_group_arn = module.alb.target_group_arn

  # Task execution & task roles
  execution_role_arn = module.iam.ecs_execution_role_arn
  api_task_role_arn  = module.iam.api_task_role_arn
  worker_task_role_arn = module.iam.worker_task_role_arn

  # Images
  api_image    = var.api_image
  worker_image = var.worker_image

  # Sizing
  api_cpu    = var.api_cpu
  api_memory = var.api_memory
  worker_cpu    = var.worker_cpu
  worker_memory = var.worker_memory

  # Scaling
  api_min_capacity    = var.api_min_capacity
  api_max_capacity    = var.api_max_capacity
  worker_min_capacity = var.worker_min_capacity
  worker_max_capacity = var.worker_max_capacity

  # Dependencies passed as env vars
  sqs_queue_url  = module.sqs.queue_url
  sqs_queue_name = module.sqs.queue_name
  db_host       = module.rds.db_endpoint
  db_name       = var.db_name
  db_username   = var.db_username
  db_password   = var.db_password
  s3_bucket     = module.s3.app_bucket_name
}

# ── 8. Monitoring ─────────────────────────────────────────────────────────────
module "monitoring" {
  source = "./modules/monitoring"

  name_prefix      = local.name_prefix
  alert_email      = var.alert_email
  sqs_queue_name   = module.sqs.queue_name
  ecs_cluster_name = module.ecs.cluster_name
  api_service_name = module.ecs.api_service_name
  worker_service_name = module.ecs.worker_service_name
  rds_identifier   = module.rds.db_identifier
  alb_arn_suffix   = module.alb.alb_arn_suffix
}
